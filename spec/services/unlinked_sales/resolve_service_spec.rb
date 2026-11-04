# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UnlinkedSales::ResolveService do
  let!(:user) { User.create!(email: 'pro@lumombeauty.com.br', name: 'Dr. Pro') }
  let!(:pipeline) { Pipeline.create!(name: 'Jornada', pipeline_type: 'sales', created_by: user) }
  let!(:stage_won) { PipelineStage.create!(pipeline: pipeline, name: 'Fechado', position: 1, stage_type: 'completed') }
  let!(:lead_a) { Contact.create!(name: 'Ana Paula Souza', phone_number: '+5561999990003') }
  let!(:lead_b) { Contact.create!(name: 'Ana Paula Souza', phone_number: '+5561999990004') }

  let(:payload) do
    {
      source: 'bitrix24', external_id: 'deal-900',
      contact: { name: 'Ana Paula Souza', external_id: 'c-900', created_at: '2026-10-13T10:00:00-03:00' },
      deal: { pipeline_id: pipeline.id, stage_id: stage_won.id, value: 1200, kind: 'sale' },
      appointments: [{ external_id: 'deal-900_eval', all_day: true, date: '2026-10-02', status: 'attended', price: 1200 }]
    }
  end

  it 'links an ambiguous sale to the chosen lead, and later syncs keep that link' do
    ExternalLeads::SyncService.new(payload).perform
    sale = UnlinkedSale.last

    result = described_class.new(sale: sale, contact: lead_b, status: 'linked').perform

    expect(result[:success]).to be(true)
    expect(sale.reload).to have_attributes(status: 'linked', resolved_contact_id: lead_b.id)
    expect(Appointment.last).to have_attributes(contact_id: lead_b.id, price: 1200)

    again = ExternalLeads::SyncService.new(payload).perform
    expect(again[:contact]).to include(id: lead_b.id)
    expect(Appointment.count).to eq(1)
  end
end
