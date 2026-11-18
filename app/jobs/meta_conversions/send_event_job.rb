# frozen_string_literal: true

class MetaConversions::SendEventJob < ApplicationJob
  queue_as :integrations

  retry_on MetaConversions::SendService::RetryableError, Net::OpenTimeout, Net::ReadTimeout,
           wait: :polynomially_longer, attempts: 5

  def perform(contact_id, event, key, value, event_time)
    contact = Contact.find_by(id: contact_id)
    return if contact.nil?

    MetaConversions::SendService.new(contact: contact, event: event, key: key, value: value, event_time: event_time).perform
  end
end
