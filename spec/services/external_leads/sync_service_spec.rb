# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/MultipleExpectations, Rails/SkipsModelValidations
RSpec.describe ExternalLeads::SyncService do
  let!(:user) { User.create!(email: 'pro@lumombeauty.com.br', name: 'Dr. Pro') }
  let!(:pipeline) { Pipeline.create!(name: 'Jornada do Paciente', pipeline_type: 'sales', created_by: user) }
  let!(:stage1) { PipelineStage.create!(pipeline: pipeline, name: '1. Novos Leads', position: 1, stage_type: 'active') }
  let!(:stage2) { PipelineStage.create!(pipeline: pipeline, name: '2. Avaliação Agendada', position: 2, stage_type: 'active') }
  let!(:stage_won) { PipelineStage.create!(pipeline: pipeline, name: '3. Fechado', position: 3, stage_type: 'completed') }

  let!(:other_pipeline) { Pipeline.create!(name: 'Outro Pipeline', pipeline_type: 'custom', created_by: user) }
  let!(:other_stage) { PipelineStage.create!(pipeline: other_pipeline, name: 'Outra Etapa', position: 1, stage_type: 'active') }

  let(:valid_payload) do
    {
      source: 'bitrix24',
      external_id: 'deal-101',
      contact: {
        name: 'Cássia Rodrigues',
        phone_number: '+5561985702132',
        email: 'cassia@example.com',
        created_at: '2026-08-15T10:30:00-03:00'
      },
      deal: {
        pipeline_id: pipeline.id,
        stage_id: stage1.id,
        value: 500.00
      }
    }
  end

  describe 'payload validation' do
    it 'fails when source is missing' do
      result = described_class.new(valid_payload.except(:source)).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('source is required')
    end

    it 'fails when external_id is missing' do
      result = described_class.new(valid_payload.except(:external_id)).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('external_id is required')
    end

    it 'fails when contact name is missing' do
      payload = valid_payload.deep_dup
      payload[:contact][:name] = nil
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('contact.name is required')
    end

    it 'fails when contact phone is not in E.164' do
      payload = valid_payload.deep_dup
      payload[:contact][:phone_number] = '61985702132'
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('contact.phone_number must be in E.164 format')
    end

    it 'fails when contact created_at is in the future' do
      payload = valid_payload.deep_dup
      payload[:contact][:created_at] = 1.day.from_now.iso8601
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('contact.created_at cannot be in the future')
    end

    it 'fails when pipeline does not exist' do
      payload = valid_payload.deep_dup
      payload[:deal][:pipeline_id] = SecureRandom.uuid
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('Pipeline not found')
    end

    it 'fails when stage does not belong to pipeline' do
      payload = valid_payload.deep_dup
      payload[:deal][:stage_id] = other_stage.id
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors]).to include('Stage not found or does not belong to this pipeline')
    end

    it 'fails when appointment status is invalid' do
      payload = valid_payload.deep_dup
      payload[:appointments] = [
        {
          external_id: 'apt-1',
          start_time: '2026-11-01T10:00:00Z',
          status: 'faltou'
        }
      ]
      result = described_class.new(payload).perform
      expect(result[:success]).to be(false)
      expect(result[:errors].any? { |e| e.include?('status is invalid') }).to be(true)
    end
  end

  describe 'idempotency and upsert' do
    it 'creates contact, deal card and external links on first call' do
      result = described_class.new(valid_payload).perform

      expect(result[:success]).to be(true)
      expect(result[:contact][:action]).to eq('created')
      expect(result[:pipeline_item][:action]).to eq('created')

      contact = Contact.find(result[:contact][:id])
      expect(contact.name).to eq('Cássia Rodrigues')
      expect(contact.phone_number).to eq(Whatsapp::PhoneNumberNormalizer.to_e164('+5561985702132'))
      expect(contact.created_at).to be_within(1.second).of(Time.zone.parse('2026-08-15T10:30:00-03:00'))

      card = PipelineItem.find(result[:pipeline_item][:id])
      expect(card.contact_id).to eq(contact.id)
      expect(card.pipeline_stage_id).to eq(stage1.id)
      expect(card.custom_fields['value']).to eq(500.00)

      link = ExternalLink.find_by(source: 'bitrix24', external_type: 'deal', external_id: 'deal-101')
      expect(link.record).to eq(card)
    end

    it 'does not duplicate records on resending identical payload' do
      res1 = described_class.new(valid_payload).perform
      expect(res1[:success]).to be(true)

      res2 = described_class.new(valid_payload).perform
      expect(res2[:success]).to be(true)
      expect(res2[:contact][:action]).to eq('unchanged')
      expect(res2[:contact][:id]).to eq(res1[:contact][:id])
      expect(res2[:pipeline_item][:action]).to eq('unchanged')
      expect(res2[:pipeline_item][:id]).to eq(res1[:pipeline_item][:id])

      expect(Contact.where(phone_number: Whatsapp::PhoneNumberNormalizer.to_e164('+5561985702132')).count).to eq(1)
      expect(PipelineItem.where(pipeline_id: pipeline.id).count).to eq(1)
      expect(ExternalLink.count).to eq(1)
    end

    it 'reuses existing contact by phone number' do
      existing = Contact.create!(name: 'Existing Name', phone_number: '+5561985702132')

      res = described_class.new(valid_payload).perform
      expect(res[:success]).to be(true)
      expect(res[:contact][:id]).to eq(existing.id)
      expect(res[:contact][:action]).to eq('updated')
      expect(existing.reload.name).to eq('Cássia Rodrigues')
    end

    it 'backfills created_at on existing contact only when older' do
      initial_time = Time.zone.parse('2026-09-01T12:00:00Z')
      contact = Contact.create!(name: 'Existing', phone_number: '+5561985702132')
      contact.update_columns(created_at: initial_time)

      # 1. Send newer date: should NOT overwrite
      payload_newer = valid_payload.deep_dup
      payload_newer[:contact][:created_at] = '2026-10-01T12:00:00Z'
      described_class.new(payload_newer).perform
      expect(contact.reload.created_at).to be_within(1.second).of(initial_time)

      # 2. Send older date: SHOULD backfill
      payload_older = valid_payload.deep_dup
      older_time = Time.zone.parse('2026-07-01T12:00:00Z')
      payload_older[:contact][:created_at] = older_time.iso8601
      described_class.new(payload_older).perform
      expect(contact.reload.created_at).to be_within(1.second).of(older_time)
    end
  end

  describe 'referral attribution' do
    it 'records first-touch attribution using external_referral' do
      payload = valid_payload.deep_dup
      payload[:referral] = {
        source_id: '120260810960180456',
        source_type: 'ad',
        source_url: 'https://fb.me/test',
        headline: 'Chamar no Whats',
        ctwa_clid: 'click-123'
      }

      res = described_class.new(payload).perform
      expect(res[:success]).to be(true)

      contact = Contact.find(res[:contact][:id])
      expect(contact.additional_attributes).to include(
        'ad_id' => '120260810960180456',
        'utm_source' => 'meta_ads',
        'utm_medium' => 'paid_social',
        'ctwa_clid' => 'click-123',
        'attribution_channel' => 'external_referral'
      )
    end
  end

  describe 'pipeline card stages' do
    it 'moves pipeline item to new stage when stage changes' do
      described_class.new(valid_payload).perform

      payload_moved = valid_payload.deep_dup
      payload_moved[:deal][:stage_id] = stage2.id
      res = described_class.new(payload_moved).perform

      expect(res[:pipeline_item][:action]).to eq('updated')
      card = PipelineItem.find(res[:pipeline_item][:id])
      expect(card.pipeline_stage_id).to eq(stage2.id)
    end

    it 'sets completed_at when moved to a completed stage' do
      described_class.new(valid_payload).perform

      payload_won = valid_payload.deep_dup
      payload_won[:deal][:stage_id] = stage_won.id
      res = described_class.new(payload_won).perform

      card = PipelineItem.find(res[:pipeline_item][:id])
      expect(card.pipeline_stage_id).to eq(stage_won.id)
      expect(card.completed_at).to be_present
    end
  end

  describe 'appointments synchronization' do
    it 'creates appointment and links to contact and card' do
      payload = valid_payload.deep_dup
      payload[:appointments] = [
        {
          external_id: 'apt-77',
          start_time: '2026-11-05T14:00:00-03:00',
          duration_minutes: 60,
          status: 'scheduled',
          price: 0.0,
          title: 'Avaliação Facial',
          professional_email: user.email
        }
      ]

      res = described_class.new(payload).perform
      expect(res[:success]).to be(true)
      expect(res[:appointments].first[:action]).to eq('created')

      apt = Appointment.find(res[:appointments].first[:id])
      expect(apt.status).to eq('scheduled')
      expect(apt.user_id).to eq(user.id)
      expect(apt.contact_id).to eq(res[:contact][:id])
      expect(apt.pipeline_item_id).to eq(res[:pipeline_item][:id])
      expect(apt.custom_attributes['source']).to eq('bitrix24')
    end

    it 'updates appointment status and price when attended' do
      payload = valid_payload.deep_dup
      payload[:appointments] = [
        {
          external_id: 'apt-77',
          start_time: '2026-11-05T14:00:00-03:00',
          status: 'scheduled',
          price: 0.0
        }
      ]
      res1 = described_class.new(payload).perform
      apt_id = res1[:appointments].first[:id]

      payload[:appointments][0][:status] = 'attended'
      payload[:appointments][0][:price] = 1500.00
      res2 = described_class.new(payload).perform

      expect(res2[:appointments].first[:id]).to eq(apt_id)
      expect(res2[:appointments].first[:action]).to eq('updated')

      apt = Appointment.find(apt_id)
      expect(apt.status).to eq('attended')
      expect(apt.price).to eq(1500.00)
    end

    it 'falls back to default user when professional_email is unknown' do
      payload = valid_payload.deep_dup
      payload[:appointments] = [
        {
          external_id: 'apt-88',
          start_time: '2026-11-05T14:00:00-03:00',
          status: 'scheduled',
          professional_email: 'unknown@example.com'
        }
      ]

      res = described_class.new(payload).perform
      expect(res[:success]).to be(true)
      apt = Appointment.find(res[:appointments].first[:id])
      expect(apt.user_id).to eq(user.id) # fell back to user
    end
  end

  describe 'atomicity' do
    it 'rolls back all changes if an appointment fails validation' do
      payload = valid_payload.deep_dup
      payload[:appointments] = [
        {
          external_id: 'apt-bad',
          start_time: nil, # invalid
          status: 'scheduled'
        }
      ]

      expect do
        res = described_class.new(payload).perform
        expect(res[:success]).to be(false)
      end.not_to change(Contact, :count)

      expect(PipelineItem.count).to eq(0)
      expect(Appointment.count).to eq(0)
      expect(ExternalLink.count).to eq(0)
    end
  end

  describe 'all-day appointments' do
    it 'stores a date-only appointment on the right calendar day in the account zone' do
      payload = valid_payload.merge(appointments: [{ external_id: 'deal_101_eval', all_day: true, date: '2026-10-07',
                                                    status: 'scheduled', professional_email: user.email }])
      result = described_class.new(payload).perform
      expect(result[:success]).to be(true)

      appointment = Appointment.last
      expect(appointment.all_day).to be(true)
      expect(appointment.start_time.in_time_zone('America/Sao_Paulo').to_date).to eq(Date.new(2026, 10, 7))
      expect(appointment.start_time.in_time_zone('America/Sao_Paulo').hour).to eq(0)
      expect(appointment.end_time.in_time_zone('America/Sao_Paulo').to_date).to eq(Date.new(2026, 10, 7))
    end

    it 'turns an all-day appointment into a timed one when the time becomes known' do
      first = valid_payload.merge(appointments: [{ external_id: 'deal_101_eval', all_day: true, date: '2026-11-20',
                                                  status: 'scheduled' }])
      described_class.new(first).perform
      timed = valid_payload.merge(appointments: [{ external_id: 'deal_101_eval', start_time: '2026-11-20T14:00:00-03:00',
                                                  duration_minutes: 45, status: 'scheduled' }])
      result = described_class.new(timed).perform

      expect(result[:appointments].first[:action]).to eq('updated')
      appointment = Appointment.last
      expect(appointment.all_day).to be(false)
      expect(appointment.start_time).to eq(Time.zone.parse('2026-11-20T14:00:00-03:00'))
      expect(Appointment.count).to eq(1)
    end

    it 'rejects a malformed date' do
      payload = valid_payload.merge(appointments: [{ external_id: 'x', all_day: true, date: '07/10/2026', status: 'scheduled' }])
      result = described_class.new(payload).perform
      expect(result[:errors]).to include('appointments[0].date must be YYYY-MM-DD')
    end
  end

  describe 'status set in the CRM' do
    it 'is never moved backwards by the sync' do
      payload = valid_payload.merge(appointments: [{ external_id: 'deal_101_eval', all_day: true, date: '2026-10-07',
                                                    status: 'scheduled' }])
      described_class.new(payload).perform
      appointment = Appointment.last
      appointment.update!(status: 'attended', custom_attributes: appointment.custom_attributes.merge('crm_override_status' => 'attended'))

      described_class.new(payload).perform
      expect(appointment.reload.status).to eq('attended')
    end
  end

  describe 'sales' do
    let!(:lead) { Contact.create!(name: 'Erilana de Lima Silva', phone_number: '+5561999990001') }

    def sale_payload(name:, external_id: 'deal-900', phone: nil)
      {
        source: 'bitrix24',
        external_id: external_id,
        contact: { name: name, phone_number: phone, external_id: 'c-900', created_at: '2026-10-13T10:00:00-03:00' },
        deal: { pipeline_id: pipeline.id, stage_id: stage_won.id, value: 4850, kind: 'sale' },
        appointments: [{ external_id: "#{external_id}_eval", all_day: true, date: '2026-10-02', status: 'attended',
                         price: 4850 }]
      }
    end

    it 'ties a phone-less sale to the lead with the same normalized name' do
      result = described_class.new(sale_payload(name: 'ERILANA DE LIMA  SILVA ')).perform

      expect(result[:success]).to be(true)
      expect(result[:contact]).to include(id: lead.id, match: 'name')
      expect(Appointment.last).to have_attributes(contact_id: lead.id, status: 'attended', price: 4850)
      expect(lead.reload.name).to eq('Erilana de Lima Silva')
      expect(Contact.count).to eq(1)
      expect(ExternalLink.find_by(external_type: 'contact', external_id: 'c-900').record).to eq(lead)
    end

    it 'matches names regardless of accents' do
      accented = Contact.create!(name: 'Lúcia Câmara', phone_number: '+5561999990002')
      result = described_class.new(sale_payload(name: 'LUCIA CAMARA')).perform
      expect(result[:contact][:id]).to eq(accented.id)
    end

    it 'queues the sale for review when the name is ambiguous, without creating a lead' do
      Contact.create!(name: 'Ana Paula Souza', phone_number: '+5561999990003')
      Contact.create!(name: 'Ana Paula Souza', phone_number: '+5561999990004')

      result = described_class.new(sale_payload(name: 'Ana Paula Souza')).perform

      expect(result).to include(success: true, queued: true)
      sale = UnlinkedSale.last
      expect(sale).to have_attributes(reason: 'ambiguous_name', amount: 4850, status: 'pending')
      expect(sale.candidate_contact_ids.size).to eq(2)
      expect(Contact.count).to eq(3)
      expect(Appointment.count).to eq(0)
    end

    it 'queues the sale when no lead matches, and is idempotent' do
      2.times { described_class.new(sale_payload(name: 'Pessoa Inexistente')).perform }

      expect(UnlinkedSale.count).to eq(1)
      expect(UnlinkedSale.last).to have_attributes(reason: 'no_match', sold_at: Time.zone.parse('2026-10-02T00:00:00-03:00'))
      expect(Contact.count).to eq(1)
    end

    it 'keeps the lead entry date' do
      lead.update_columns(created_at: Time.zone.parse('2026-10-20T10:00:00-03:00'))
      described_class.new(sale_payload(name: 'Erilana de Lima Silva')).perform
      expect(lead.reload.created_at).to eq(Time.zone.parse('2026-10-20T10:00:00-03:00'))
    end
  end

  describe 'repurchase' do
    it 'marks a contact created by a repurchase as a returning customer' do
      payload = valid_payload.deep_merge(deal: { kind: 'repurchase' })
      described_class.new(payload).perform
      expect(Contact.last.custom_attributes['customer_type']).to eq('returning')
    end
  end

  describe 'inferred origin' do
    it 'records the origin from the source CRM when there is no ad referral' do
      payload = valid_payload.merge(referral_fallback: { source: 'instagram' })
      described_class.new(payload).perform

      attrs = Contact.last.additional_attributes
      expect(attrs).to include('utm_source' => 'instagram', 'attribution_channel' => 'external_fallback')
    end

    it 'is replaced by the real ad when it shows up later' do
      described_class.new(valid_payload.merge(referral_fallback: { source: 'meta_ads' })).perform
      described_class.new(valid_payload.merge(referral: { source_id: '120260810960180456', source_type: 'ad' })).perform

      attrs = Contact.last.additional_attributes
      expect(attrs).to include('utm_source' => 'meta_ads', 'ad_id' => '120260810960180456',
                               'attribution_channel' => 'external_referral')
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, Rails/SkipsModelValidations
