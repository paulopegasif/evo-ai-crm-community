# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PipelineItem, 'services catalog integration', type: :model do
  let(:user) { User.create!(email: 'svc-test@example.com', name: 'Test User') }
  let(:pipeline) do
    Pipeline.create!(name: 'Test Pipeline', pipeline_type: 'sales', created_by: user)
  end
  let(:stage) { PipelineStage.create!(pipeline: pipeline, name: 'Stage 1', position: 1) }
  let(:contact) { Contact.create!(name: 'Test Contact', email: 'contact@test.com') }

  describe '#normalize_services_data!' do
    it 'creates catalog entry when saving service without service_definition_id' do
      item = PipelineItem.new(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => 'Consulting', 'value' => '150.00' }]
        }
      )

      expect { item.save! }.to change(PipelineServiceDefinition, :count).by(1)

      catalog = PipelineServiceDefinition.last
      expect(catalog.name).to eq('Consulting')
      expect(catalog.default_value).to eq(150.0)
      expect(catalog.pipeline).to eq(pipeline)
    end

    it 'links service_definition_id to the service data' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => 'Consulting', 'value' => '150.00' }]
        }
      )

      service = item.reload.custom_fields['services'].first
      expect(service['service_definition_id']).to be_present
    end

    it 'reuses existing catalog entry for same service name' do
      existing = pipeline.pipeline_service_definitions.create!(
        name: 'Consulting', default_value: 100.00, currency: 'BRL'
      )

      item = PipelineItem.new(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => 'Consulting', 'value' => '200.00' }]
        }
      )

      expect { item.save! }.not_to change(PipelineServiceDefinition, :count)

      service = item.reload.custom_fields['services'].first
      expect(service['service_definition_id']).to eq(existing.id.to_s)
    end

    it 'preserves service_definition_id when already present' do
      existing = pipeline.pipeline_service_definitions.create!(
        name: 'Consulting', default_value: 100.00, currency: 'BRL'
      )

      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => 'Consulting', 'value' => '200.00', 'service_definition_id' => existing.id.to_s }]
        }
      )

      expect { item.save! }.not_to change(PipelineServiceDefinition, :count)

      service = item.reload.custom_fields['services'].first
      expect(service['service_definition_id']).to eq(existing.id.to_s)
    end

    it 'normalizes value to 2 decimal places string' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => 'Service', 'value' => '99.999' }]
        }
      )

      service = item.reload.custom_fields['services'].first
      expect(service['value'].to_f).to eq(100.0)
    end

    it 'strips whitespace from service names' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => '  Consulting  ', 'value' => '100' }]
        }
      )

      service = item.reload.custom_fields['services'].first
      expect(service['name']).to eq('Consulting')
    end

    it 'removes services array when all entries are invalid' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [{ 'name' => '', 'value' => '100' }]
        }
      )

      expect(item.reload.custom_fields).not_to have_key('services')
    end

    it 'handles multiple services creating multiple catalog entries' do
      item = PipelineItem.new(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [
            { 'name' => 'Consulting', 'value' => '150' },
            { 'name' => 'Support', 'value' => '80' }
          ]
        }
      )

      expect { item.save! }.to change(PipelineServiceDefinition, :count).by(2)
    end
  end

  describe '#services_total_value' do
    it 'sums all service values' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'services' => [
            { 'name' => 'A', 'value' => '100.50' },
            { 'name' => 'B', 'value' => '200.25' }
          ]
        }
      )

      expect(item.services_total_value).to eq(300.75)
    end

    it 'returns 0 when no services and no value' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {}
      )

      expect(item.services_total_value).to eq(0)
    end

    it 'falls back to custom_fields value when services is absent' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: { 'value' => 1500.50 }
      )

      expect(item.services_total_value).to eq(1500.50)
    end

    it 'prefers positive services total over custom_fields value' do
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact,
        custom_fields: {
          'value' => 1000.0,
          'services' => [
            { 'name' => 'Procedimento Especial', 'value' => '2500.00' }
          ]
        }
      )

      expect(item.services_total_value).to eq(2500.0)
    end
  end

  describe '#find_or_create_catalog_service' do
    it 'handles errors gracefully and returns nil' do
      item = PipelineItem.new(
        pipeline: pipeline,
        pipeline_stage: stage,
        contact: contact
      )

      # Force an error by making pipeline_service_definitions raise
      allow(pipeline.pipeline_service_definitions).to receive(:find_by).and_raise(StandardError, 'DB error')

      result = item.find_or_create_catalog_service('Test', 100.0)
      expect(result).to be_nil
    end

    it 'returns nil when pipeline is nil' do
      item = PipelineItem.new(
        pipeline_stage: stage,
        contact: contact
      )
      item.pipeline = nil

      result = item.find_or_create_catalog_service('Test', 100.0)
      expect(result).to be_nil
    end
  end
end
