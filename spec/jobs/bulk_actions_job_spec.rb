# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkActionsJob do
  let(:user) { User.create!(email: "admin-#{SecureRandom.hex(4)}@example.com", name: 'Admin') }
  let(:pipeline) { Pipeline.create!(name: "Vendas #{SecureRandom.hex(3)}", pipeline_type: 'sales', created_by: user) }
  let(:stage) { PipelineStage.create!(pipeline: pipeline, name: 'Novo Lead', position: 1) }

  def contact
    Contact.create!(name: "Lead #{SecureRandom.hex(3)}", email: "lead-#{SecureRandom.hex(4)}@example.com")
  end

  def delete(ids)
    described_class.perform_now(user: user, params: { type: 'Contact', ids: ids, fields: { action: 'delete' } })
  end

  it 'deletes contacts that are in a pipeline' do
    in_pipeline = contact
    plain = contact
    PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage, contact: in_pipeline)

    delete([in_pipeline.id, plain.id])

    expect(Contact.where(id: [in_pipeline.id, plain.id])).to be_empty
    expect(PipelineItem.where(contact_id: in_pipeline.id)).to be_empty
  end

  it 'returns the deleted ids and keeps going when one contact fails' do
    ok = contact
    broken = contact
    allow_any_instance_of(Contact).to receive(:destroy_with_dependents!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordNotDestroyed, 'boom' if original.receiver.id == broken.id

      original.call(*args)
    end

    result = delete([broken.id, ok.id])

    expect(result).to eq(success_ids: [ok.id], failed_ids: [broken.id])
    expect(Contact.exists?(ok.id)).to be(false)
    expect(Contact.exists?(broken.id)).to be(true)
  end
end
