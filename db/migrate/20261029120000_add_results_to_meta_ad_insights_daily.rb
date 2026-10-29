# frozen_string_literal: true

# Results Meta reports per ad and day (Click-to-WhatsApp conversations, lead
# forms, link clicks), plus the raw `actions` list for metrics added later.
class AddResultsToMetaAdInsightsDaily < ActiveRecord::Migration[7.1]
  def change
    change_table :meta_ad_insights_daily, bulk: true do |t|
      t.bigint :link_clicks, default: 0, null: false
      t.bigint :conversations, default: 0, null: false
      t.bigint :meta_leads, default: 0, null: false
      t.jsonb :actions, default: [], null: false
    end
  end
end
