# Edits a message's text. Private notes are edited in the CRM only; outgoing
# WhatsApp text messages are edited on WhatsApp first and only updated locally
# once the provider accepts the edit (so the CRM never shows text the contact
# didn't get). Raises Messages::EditService::Error with a user-facing reason.
class Messages::EditService
  class Error < StandardError; end

  # WhatsApp only allows editing a sent message for 15 minutes.
  WHATSAPP_EDIT_WINDOW = 15.minutes

  def initialize(message, new_content)
    @message = message
    @new_content = new_content.to_s.strip
  end

  def perform
    raise Error, 'Content cannot be blank' if @new_content.blank?

    reason = rejection_reason
    raise Error, reason if reason
    return @message if @new_content == @message.content

    channel.edit_message(@message, @new_content) unless @message.private?

    @message.update!(
      content: @new_content,
      is_edited: true,
      previous_content: @message.previous_content.presence || @message.content
    )
    @message
  end

  private

  def channel
    @message.conversation.inbox.channel
  end

  def rejection_reason
    return 'Deleted messages cannot be edited' if @message.content_attributes&.dig('deleted')
    return 'Only text messages can be edited' if @message.attachments.any? || !@message.text?
    return nil if @message.private?
    return 'Only outgoing messages can be edited' unless @message.outgoing?

    whatsapp_rejection_reason
  end

  def whatsapp_rejection_reason
    return 'Editing is not supported on this channel' unless channel.respond_to?(:supports_message_edit?) && channel.supports_message_edit?
    return 'Message was not delivered to WhatsApp' if @message.failed? || @message.source_id.blank?
    return 'WhatsApp only allows editing within 15 minutes' if @message.created_at < WHATSAPP_EDIT_WINDOW.ago

    nil
  end
end
