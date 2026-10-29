# frozen_string_literal: true

class CreateExternalLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :external_links, id: :uuid, if_not_exists: true do |t|
      t.string :source, null: false, limit: 100
      t.string :external_type, null: false, limit: 100
      t.string :external_id, null: false, limit: 255
      t.string :record_type, null: false, limit: 100
      t.uuid :record_id, null: false

      t.timestamps
    end

    add_index :external_links, %i[source external_type external_id],
              name: 'index_external_links_on_source_and_type_and_external_id',
              unique: true,
              if_not_exists: true

    add_index :external_links, %i[record_type record_id],
              name: 'index_external_links_on_record_type_and_record_id',
              if_not_exists: true
  end
end
