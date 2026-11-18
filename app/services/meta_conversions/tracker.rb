# frozen_string_literal: true

# Turns CRM milestones of a lead into Conversions API events and queues them:
# - lead:      the contact got its ad attribution (first touch with ctwa_clid)
# - qualified: first appointment, or the card reached a stage that counts as qualified
# - purchase:  an attended appointment with a price (same rule as the Tracking dashboard)
# Each key is sent at most once per contact. Errors here never break the CRM write.
module MetaConversions::Tracker
  module_function

  # Meta rejects events whose event_time is older than 7 days.
  MAX_EVENT_AGE = 7.days
  # A purchase confirmed later than this after the appointment is not reported.
  MAX_PURCHASE_DELAY = 30.days
  # Lets the transaction that triggered the event commit before the job reads it.
  ENQUEUE_DELAY = 1.minute

  def lead(contact)
    return if contact.nil?

    track(contact, 'lead', 'lead', occurred_at: [contact.created_at, Time.current].min)
  end

  def qualified(contact)
    track(contact, 'qualified', 'qualified', occurred_at: Time.current)
  end

  def purchase(appointment)
    contact = appointment.contact
    happened = appointment.start_time || Time.current
    return if happened < MAX_PURCHASE_DELAY.ago

    occurred_at = happened > MAX_EVENT_AGE.ago ? [happened, Time.current].min : Time.current
    track(contact, 'purchase', "purchase:#{appointment.id}", occurred_at: occurred_at, value: appointment.price.to_f)
  end

  def track(contact, event, key, occurred_at:, value: nil)
    return unless eligible?(contact, key, occurred_at)

    MetaConversions::SendEventJob.set(wait: ENQUEUE_DELAY)
                                 .perform_later(contact.id, event, key, value, occurred_at.to_i)
  rescue StandardError => e
    Rails.logger.error("MetaConversions::Tracker #{event} for contact #{contact&.id} not queued: #{e.message}")
  end

  def eligible?(contact, key, occurred_at)
    return false unless MetaConversions::Config.enabled?
    return false if contact.nil? || sent?(contact, key)
    return false if occurred_at < MAX_EVENT_AGE.ago || contact.created_at < MetaConversions::Config.max_lead_age.ago

    MetaConversions::Identity.new(contact).sendable?
  end

  def sent?(contact, key)
    (contact.additional_attributes || {}).dig('meta_capi', key, 'sent_at').present?
  end
end
