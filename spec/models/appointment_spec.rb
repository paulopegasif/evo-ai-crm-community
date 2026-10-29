# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Appointment, type: :model do
  let(:user) { User.create!(email: 'pro@example.com', name: 'Professional') }
  let(:contact) { Contact.create!(name: 'Client', phone_number: '+5561999990001') }

  describe '#sync_google_calendar?' do
    it 'returns true when custom_attributes has no source' do
      appointment = described_class.new(
        title: 'Consulta Normal',
        user: user,
        contact: contact,
        start_time: 1.day.from_now,
        category: 'Geral',
        status: 'scheduled',
        custom_attributes: {}
      )

      expect(appointment.sync_google_calendar?).to be(true)
    end

    it 'returns false when custom_attributes has source present' do
      appointment = described_class.new(
        title: 'Consulta Externa',
        user: user,
        contact: contact,
        start_time: 1.day.from_now,
        category: 'Geral',
        status: 'scheduled',
        custom_attributes: { 'source' => 'bitrix24' }
      )

      expect(appointment.sync_google_calendar?).to be(false)
    end
  end
end
