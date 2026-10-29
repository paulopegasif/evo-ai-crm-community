# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/ExampleLength
RSpec.describe ExternalLink, type: :model do
  let(:contact) { Contact.create!(name: 'Test Contact', email: "contact-#{SecureRandom.hex(4)}@example.com") }

  describe 'validations' do
    it 'is valid with valid attributes' do
      link = described_class.new(
        source: 'bitrix24',
        external_type: 'deal',
        external_id: '12345',
        record: contact
      )
      expect(link).to be_valid
    end

    it 'requires source' do
      link = described_class.new(source: nil, external_type: 'deal', external_id: '12345', record: contact)
      expect(link).not_to be_valid
      expect(link.errors[:source]).to be_present
    end

    it 'requires external_type' do
      link = described_class.new(source: 'bitrix24', external_type: nil, external_id: '12345', record: contact)
      expect(link).not_to be_valid
      expect(link.errors[:external_type]).to be_present
    end

    it 'requires external_id' do
      link = described_class.new(source: 'bitrix24', external_type: 'deal', external_id: nil, record: contact)
      expect(link).not_to be_valid
      expect(link.errors[:external_id]).to be_present
    end

    it 'enforces uniqueness of external_id scoped to source and external_type' do
      described_class.create!(
        source: 'bitrix24',
        external_type: 'deal',
        external_id: '12345',
        record: contact
      )

      duplicate = described_class.new(
        source: 'bitrix24',
        external_type: 'deal',
        external_id: '12345',
        record: contact
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to be_present

      # Different external_type is allowed
      other_type = described_class.new(
        source: 'bitrix24',
        external_type: 'appointment',
        external_id: '12345',
        record: contact
      )
      expect(other_type).to be_valid

      # Different source is allowed
      other_source = described_class.new(
        source: 'hubspot',
        external_type: 'deal',
        external_id: '12345',
        record: contact
      )
      expect(other_source).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to record polymorphically' do
      link = described_class.create!(
        source: 'bitrix24',
        external_type: 'deal',
        external_id: 'deal-99',
        record: contact
      )
      expect(link.record).to eq(contact)
      expect(link.record_type).to eq('Contact')
      expect(link.record_id).to eq(contact.id)
    end
  end
end
# rubocop:enable RSpec/ExampleLength
