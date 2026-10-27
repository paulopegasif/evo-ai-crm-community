# frozen_string_literal: true

# Local copy of the connected Meta ad account (campaign -> ad set -> ad) and its
# daily delivery metrics, synced by MetaAds::SyncJob. Rows are linked by Meta ids
# (strings) instead of foreign keys so an ad can arrive before its campaign and
# leads carrying a not-yet-synced ad id keep working.
class CreateMetaAdsTables < ActiveRecord::Migration[7.1]
  def change
    create_table :meta_campaigns, id: :uuid do |t|
      t.string :meta_id, null: false
      t.string :ad_account_id, null: false
      t.string :name
      t.string :status
      t.string :effective_status
      t.string :objective
      t.datetime :created_time
      t.datetime :updated_time
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :meta_campaigns, :meta_id, unique: true
    add_index :meta_campaigns, :ad_account_id

    create_table :meta_adsets, id: :uuid do |t|
      t.string :meta_id, null: false
      t.string :meta_campaign_id
      t.string :name
      t.string :status
      t.string :effective_status
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :meta_adsets, :meta_id, unique: true
    add_index :meta_adsets, :meta_campaign_id

    create_table :meta_ads, id: :uuid do |t|
      t.string :meta_id, null: false
      t.string :meta_adset_id
      t.string :meta_campaign_id
      t.string :name
      t.string :status
      t.string :effective_status
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :meta_ads, :meta_id, unique: true
    add_index :meta_ads, :meta_adset_id
    add_index :meta_ads, :meta_campaign_id

    create_table :meta_ad_insights_daily, id: :uuid do |t|
      t.string :meta_ad_id, null: false
      t.string :meta_campaign_id
      t.date :date, null: false
      t.decimal :spend, precision: 14, scale: 2, null: false, default: 0
      t.bigint :impressions, null: false, default: 0
      t.bigint :reach, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.string :currency
      t.timestamps
    end
    add_index :meta_ad_insights_daily, %i[meta_ad_id date], unique: true
    add_index :meta_ad_insights_daily, %i[meta_campaign_id date]
  end
end
