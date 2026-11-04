# frozen_string_literal: true

# Where a lead came from (first touch) and what it is estimated to have cost.
#
# Estimated cost of an ad lead = cost per conversation of its ad on the day the
# lead entered (spend ÷ conversations of that ad that day). Fallbacks: the
# campaign on that day, then the campaign over the requested period. Leads that
# did not come from an ad have no cost.
#
#   LeadOrigin.for(contact)               # => { source:, campaign:, ad:, estimated_cost:, cost_basis:, ... }
#   LeadOrigin.batch(contacts, period: r) # => { contact_id => origin }
class LeadOrigin
  SOURCE_LABELS = {
    'meta_ads' => 'Meta Ads', 'instagram' => 'Instagram', 'phone' => 'Telefone',
    'google' => 'Google', 'referral' => 'Indicação', 'site' => 'Site'
  }.freeze
  UNKNOWN_SOURCE = 'Não informada'

  def self.for(contact)
    return nil if contact.nil?

    batch([contact])[contact.id]
  end

  def self.batch(contacts, period: nil)
    new(contacts, period: period).call
  end

  def self.source_label(raw)
    return UNKNOWN_SOURCE if raw.blank?

    SOURCE_LABELS[raw] || (raw.start_with?('bitrix:') ? raw.delete_prefix('bitrix:').humanize : raw)
  end

  def initialize(contacts, period: nil)
    @contacts = Array(contacts).compact
    @period = period
  end

  def call
    @contacts.to_h { |contact| [contact.id, origin_for(contact)] }
  end

  private

  def origin_for(contact)
    attrs = contact.additional_attributes || {}
    ad = ads[attrs['ad_id']]
    campaign_id = ad&.meta_campaign_id
    cost, basis = estimated_cost(attrs['ad_id'], campaign_id, local_day(contact.created_at))

    {
      source: self.class.source_label(attrs['utm_source'].presence || contact.custom_attributes&.dig('utm_source')),
      channel: attrs['attribution_channel'],
      ad_id: attrs['ad_id'],
      ad_name: ad&.name,
      ad_headline: attrs['ad_headline'],
      ad_source_url: attrs['ad_source_url'],
      ctwa_clid: attrs['ctwa_clid'],
      adset_id: ad&.meta_adset_id,
      adset_name: adsets[ad&.meta_adset_id],
      campaign_id: campaign_id,
      campaign_name: campaigns[campaign_id] || attrs['utm_campaign'],
      ad_unavailable: attrs['ad_id'].present? && (ad.nil? || ad.effective_status == MetaAds::Ad::UNAVAILABLE),
      attributed_at: attrs['attributed_at'],
      entered_at: contact.created_at&.iso8601,
      estimated_cost: cost,
      cost_basis: basis
    }
  end

  def local_day(time)
    time&.in_time_zone(AccountTime.zone)&.to_date
  end

  def estimated_cost(ad_id, campaign_id, day)
    return [nil, nil] if ad_id.blank? || day.nil?

    per_conversation(ad_day[[ad_id, day]], 'ad_day') ||
      (campaign_id && per_conversation(campaign_day[[campaign_id, day]], 'campaign_day')) ||
      (campaign_id && per_conversation(campaign_period[campaign_id], 'campaign_period')) ||
      [nil, nil]
  end

  def per_conversation(totals, basis)
    return nil if totals.nil? || totals[1].to_i.zero?

    [(totals[0].to_f / totals[1]).round(2), basis]
  end

  def ad_ids
    @ad_ids ||= @contacts.filter_map { |c| c.additional_attributes&.dig('ad_id').presence }.uniq
  end

  def ads
    @ads ||= MetaAds::Ad.where(meta_id: ad_ids).index_by(&:meta_id)
  end

  def campaigns
    @campaigns ||= MetaAds::Campaign.where(meta_id: ads.values.filter_map(&:meta_campaign_id)).pluck(:meta_id, :name).to_h
  end

  def adsets
    @adsets ||= MetaAds::Adset.where(meta_id: ads.values.filter_map(&:meta_adset_id)).pluck(:meta_id, :name).to_h
  end

  def days
    @days ||= @contacts.filter_map { |c| local_day(c.created_at) }.uniq
  end

  def insights
    MetaAds::InsightDaily.where(date: days)
  end

  def ad_day
    @ad_day ||= insights.where(meta_ad_id: ad_ids).group(:meta_ad_id, :date)
                        .pluck(:meta_ad_id, :date, Arel.sql('SUM(spend)'), Arel.sql('SUM(conversations)'))
                        .to_h { |id, date, spend, conv| [[id, date], [spend, conv]] }
  end

  def campaign_ids
    ads.values.filter_map(&:meta_campaign_id).uniq
  end

  def campaign_day
    @campaign_day ||= insights.where(meta_campaign_id: campaign_ids).group(:meta_campaign_id, :date)
                              .pluck(:meta_campaign_id, :date, Arel.sql('SUM(spend)'), Arel.sql('SUM(conversations)'))
                              .to_h { |id, date, spend, conv| [[id, date], [spend, conv]] }
  end

  def campaign_period
    @campaign_period ||= begin
      range = @period || (days.min..days.max)
      MetaAds::InsightDaily.where(date: range, meta_campaign_id: campaign_ids).group(:meta_campaign_id)
                           .pluck(:meta_campaign_id, Arel.sql('SUM(spend)'), Arel.sql('SUM(conversations)'))
                           .to_h { |id, spend, conv| [id, [spend, conv]] }
    end
  end
end
