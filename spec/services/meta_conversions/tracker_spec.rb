# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetaConversions::Tracker do
  let(:settings) do
    { 'META_CAPI_ENABLED' => 'true', 'META_CAPI_DATASET_ID' => '111', 'META_CAPI_ACCESS_TOKEN' => 'tok', 'META_CAPI_WABA_ID' => '222' }
  end
  let!(:user) { User.create!(email: 'pro@lumombeauty.com.br', name: 'Dr. Pro') }
  let(:contact) do
    Contact.create!(name: 'Lead Anúncio', phone_number: '+5561985702132', additional_attributes: { 'ctwa_clid' => 'ARAk-click' })
  end

  before do
    allow(MetaConversions::Config).to receive(:env) { |key| settings[key] }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == MetaConversions::SendEventJob }
  end

  def queued_events
    jobs.map { |j| j[:args][1] }
  end

  def appointment!(attrs = {})
    Appointment.create!({ user: user, contact: contact, title: 'Avaliação', category: 'Geral',
                          start_time: 1.day.from_now, status: 'scheduled' }.merge(attrs))
  end

  it 'queues nothing while disabled' do
    settings['META_CAPI_ENABLED'] = 'false'
    described_class.lead(contact)
    expect(jobs).to be_empty
  end

  it 'queues a lead event once per contact' do
    described_class.lead(contact)
    expect(queued_events).to eq(['lead'])

    sent = contact.additional_attributes.merge('meta_capi' => { 'lead' => { 'sent_at' => Time.current.iso8601 } })
    contact.update_columns(additional_attributes: sent) # rubocop:disable Rails/SkipsModelValidations
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.lead(contact)
    expect(jobs).to be_empty
  end

  it 'skips leads older than the configured age' do
    contact.update_columns(created_at: 120.days.ago) # rubocop:disable Rails/SkipsModelValidations
    described_class.qualified(contact)
    expect(jobs).to be_empty
  end

  it 'skips contacts Meta cannot match, unless a page id allows phone matching' do
    contact.update_columns(additional_attributes: {}) # rubocop:disable Rails/SkipsModelValidations
    described_class.qualified(contact)
    expect(jobs).to be_empty

    settings['META_CAPI_PAGE_ID'] = '333'
    described_class.qualified(contact)
    expect(queued_events).to eq(['qualified'])
  end

  it 'queues the lead event when the contact gets a Click-to-WhatsApp attribution' do
    fresh = Contact.create!(name: 'Novo Lead', phone_number: '+5561999990000')
    Attribution::RecordService.new(contact: fresh, touch: { 'source_id' => '123', 'ctwa_clid' => 'ARAk-new' },
                                   source: :external_referral).perform
    expect(queued_events).to eq(['lead'])
  end

  it 'queues qualified on the first appointment and purchase when attended with a price' do
    appointment = appointment!
    expect(queued_events).to eq(['qualified'])

    appointment.update!(status: 'attended', price: 1200, start_time: 1.hour.ago)
    purchase = jobs.find { |j| j[:args][1] == 'purchase' }
    expect(purchase[:args][2]).to eq("purchase:#{appointment.id}")
    expect(purchase[:args][3]).to eq(1200.0)
  end

  it 'does not report a purchase confirmed long after the appointment' do
    appointment = appointment!(start_time: 40.days.ago, status: 'cancelled')
    appointment.update!(status: 'attended', price: 500)
    expect(queued_events).not_to include('purchase')
  end

  it 'queues qualified when the card reaches a stage that counts as qualified' do
    pipeline = Pipeline.create!(name: 'Jornada', pipeline_type: 'sales', created_by: user)
    novo = PipelineStage.create!(pipeline: pipeline, name: 'Novo', position: 1, stage_type: 'active')
    qualificado = PipelineStage.create!(pipeline: pipeline, name: 'Qualificado', position: 2, stage_type: 'active', counts_as_qualified: true)
    item = pipeline.pipeline_items.create!(contact: contact, pipeline_stage: novo, entered_at: Time.current)
    expect(jobs).to be_empty

    item.update!(pipeline_stage: qualificado)
    expect(queued_events).to eq(['qualified'])
  end
end
