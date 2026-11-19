# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetaConversions::Config do
  let(:env) do
    { 'META_CAPI_ENABLED' => 'true', 'META_CAPI_DATASET_ID' => 'env-ds', 'META_CAPI_ACCESS_TOKEN' => 'env-tok',
      'META_CAPI_WABA_ID' => 'env-waba' }
  end

  before { allow(described_class).to receive(:env) { |key| env[key] } }

  it 'uses the environment while the integrations page was never saved' do
    expect(described_class.enabled?).to be(true)
    expect(described_class.dataset_id).to eq('env-ds')
  end

  it 'prefers the saved integration, even when it is turned off' do
    Integrations::Hook.create!(app_id: 'meta_conversions', settings: {
                                 'enabled' => false, 'waba_id' => '102290129340398', 'dataset_id' => 'ui-ds',
                                 'access_token_encrypted' => MetaAds::Credentials.encrypt('ui-tok')
                               })

    expect(described_class.enabled?).to be(false)
    expect(described_class.dataset_id).to eq('ui-ds')
    expect(described_class.access_token).to eq('ui-tok')
    expect(described_class.page_id).to be_nil
  end

  it 'is enabled from the saved integration when it is complete' do
    Integrations::Hook.create!(app_id: 'meta_conversions', settings: {
                                 'enabled' => true, 'waba_id' => '102290129340398', 'dataset_id' => 'ui-ds',
                                 'access_token_encrypted' => MetaAds::Credentials.encrypt('ui-tok')
                               })
    expect(described_class.enabled?).to be(true)
  end
end
