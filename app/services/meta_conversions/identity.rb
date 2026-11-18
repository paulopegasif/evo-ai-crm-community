# frozen_string_literal: true

# How Meta can tie a contact to the ad click: the Click-to-WhatsApp click id
# (ctwa_clid) when the lead came from an ad, otherwise the hashed phone number,
# which needs META_CAPI_PAGE_ID and only attributes interactions of the last 7 days.
class MetaConversions::Identity
  def initialize(contact)
    @contact = contact
  end

  def sendable?
    ctwa_clid.present? || phone_matchable?
  end

  def ctwa_clid
    attrs = @contact.additional_attributes || {}
    attrs['ctwa_clid'].presence || attrs.dig('last_touch', 'ctwa_clid').presence
  end

  def user_data
    data = { whatsapp_business_account_id: MetaConversions::Config.waba_id }
    return data.merge(ctwa_clid: ctwa_clid) if ctwa_clid.present?

    data.merge(page_id: MetaConversions::Config.page_id, ph: [hashed_phone])
  end

  private

  def phone_matchable?
    MetaConversions::Config.page_id.present? && phone_digits.present?
  end

  # Meta expects digits only, with country code, then SHA-256.
  def phone_digits
    @contact.phone_number.to_s.gsub(/\D/, '').presence
  end

  def hashed_phone
    Digest::SHA256.hexdigest(phone_digits)
  end
end
