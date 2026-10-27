# frozen_string_literal: true

# Lead attribution: joins contacts to synced Meta ads by the first-touch ad id
# stored in additional_attributes (see Attribution::RecordService).
class AddAdIdIndexToContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :contacts, "(additional_attributes->>'ad_id')",
              name: 'index_contacts_on_attribution_ad_id',
              where: "additional_attributes ? 'ad_id'",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
