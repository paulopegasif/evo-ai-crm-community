# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Attribution::RecordService do
  let(:contact) { Contact.create!(name: 'Maria Lead', phone_number: '+5561999990001') }
  let(:referral_a) do
    {
      source_url: 'https://fb.me/abc',
      source_id: '120200000000001',
      source_type: 'ad',
      headline: 'Botox com 20% off',
      ctwa_clid: 'ARAkLkA8rmlFeiCktEJQ'
    }
  end
  let(:referral_b) { referral_a.merge(source_id: '120200000000002', ctwa_clid: 'other-clid') }

  def record(touch, source: :whatsapp_referral)
    described_class.new(contact: contact, touch: touch, source: source).perform
    contact.reload.additional_attributes
  end

  describe 'WhatsApp Cloud API referral' do
    it 'stores the first-touch origin from a click-to-WhatsApp ad' do
      attrs = record(referral_a)

      expect(attrs).to include(
        'utm_source' => 'meta_ads',
        'utm_medium' => 'paid_social',
        'ad_id' => '120200000000001',
        'ad_source_type' => 'ad',
        'ad_source_url' => 'https://fb.me/abc',
        'ad_headline' => 'Botox com 20% off',
        'ctwa_clid' => 'ARAkLkA8rmlFeiCktEJQ',
        'attribution_channel' => 'whatsapp_referral'
      )
      expect(attrs['attributed_at']).to be_present
      expect(attrs.dig('last_touch', 'ad_id')).to eq('120200000000001')
    end

    it 'maps boosted posts to the social medium' do
      expect(record(referral_a.merge(source_type: 'post'))['utm_medium']).to eq('social')
    end

    it 'keeps the first touch and only refreshes last_touch on a later ad click' do
      record(referral_a)
      attrs = record(referral_b)

      expect(attrs['ad_id']).to eq('120200000000001')
      expect(attrs['ctwa_clid']).to eq('ARAkLkA8rmlFeiCktEJQ')
      expect(attrs.dig('last_touch', 'ad_id')).to eq('120200000000002')
    end

    it 'preserves unrelated additional attributes' do
      contact.update!(additional_attributes: { 'company' => 'Lumom' })

      expect(record(referral_a)).to include('company' => 'Lumom', 'ad_id' => '120200000000001')
    end

    it 'ignores a referral without source_id nor ctwa_clid' do
      expect(described_class.new(contact: contact, touch: { headline: 'x' }, source: :whatsapp_referral).perform).to be(false)
      expect(contact.reload.additional_attributes).to eq({})
    end
  end

  describe 'UTMs from forms and the public leads API' do
    it 'stores utm parameters and fbclid as first touch' do
      attrs = record({ 'utm_source' => 'facebook', 'utm_campaign' => 'botox-outubro', 'fbclid' => 'IwAR1', 'foo' => 'bar' },
                     source: :public_api)

      expect(attrs).to include('utm_source' => 'facebook', 'utm_campaign' => 'botox-outubro', 'fbclid' => 'IwAR1',
                               'attribution_channel' => 'public_api')
      expect(attrs).not_to have_key('foo')
    end

    it 'does nothing without utm parameters' do
      expect(described_class.new(contact: contact, touch: { 'name' => 'x' }, source: :form).perform).to be(false)
      expect(contact.reload.additional_attributes).to eq({})
    end

    it 'does not overwrite an ad first-touch with a later form submission' do
      record(referral_a)
      attrs = record({ 'utm_source' => 'google', 'utm_campaign' => 'search' }, source: :form)

      expect(attrs['utm_source']).to eq('meta_ads')
      expect(attrs.dig('last_touch', 'utm_source')).to eq('google')
    end
  end
end
