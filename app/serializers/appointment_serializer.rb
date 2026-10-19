# frozen_string_literal: true

module AppointmentSerializer
  extend self

  def serialize(appointment)
    return nil if appointment.nil?

    {
      id: appointment.id,
      title: appointment.title,
      description: appointment.description,
      category: appointment.category,
      start_time: appointment.start_time&.iso8601,
      end_time: appointment.end_time&.iso8601,
      start_timestamp: appointment.start_time&.to_i,
      end_timestamp: appointment.end_time&.to_i,
      duration_minutes: appointment.duration_minutes,
      status: appointment.status,
      user_id: appointment.user_id,
      user: appointment.user ? {
        id: appointment.user.id,
        name: appointment.user.name,
        display_name: appointment.user.display_name,
        email: appointment.user.email,
        avatar_url: appointment.user.avatar_url
      } : nil,
      contact_id: appointment.contact_id,
      contact: appointment.contact ? {
        id: appointment.contact.id,
        name: appointment.contact.name,
        email: appointment.contact.email,
        phone_number: appointment.contact.phone_number
      } : nil,
      conversation_id: appointment.conversation_id,
      pipeline_item_id: appointment.pipeline_item_id,
      google_calendar_event_id: appointment.google_calendar_event_id,
      google_calendar_sync_status: appointment.google_calendar_sync_status,
      google_calendar_url: appointment.google_calendar_url,
      google_meet_link: appointment.google_meet_link,
      location: appointment.location,
      price: appointment.price.to_f,
      custom_attributes: appointment.custom_attributes || {},
      created_at: appointment.created_at.to_i,
      updated_at: appointment.updated_at.to_i
    }
  end

  def serialize_collection(appointments)
    appointments.map { |appointment| serialize(appointment) }
  end
end
