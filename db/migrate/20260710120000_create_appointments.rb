# frozen_string_literal: true

class CreateAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :appointments, id: :uuid, if_not_exists: true do |t|
      t.string :title, null: false, limit: 255
      t.text :description
      t.string :category, null: false, default: 'Geral', limit: 100
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :duration_minutes, null: false, default: 60
      t.string :status, null: false, default: 'scheduled', limit: 50
      
      # Professional / Team Member (User)
      t.uuid :user_id, null: false
      
      # Client / Contact
      t.uuid :contact_id
      
      # Optional CRM connections
      t.uuid :conversation_id
      t.uuid :pipeline_item_id
      
      # Google Calendar sync fields
      t.string :google_calendar_event_id, limit: 255
      t.string :google_calendar_sync_status, default: 'pending', limit: 50
      t.string :google_meet_link, limit: 500
      t.string :location, limit: 255
      
      # Commercial / Aesthetic pricing
      t.decimal :price, precision: 10, scale: 2, default: 0.0, null: false
      
      # Custom metadata / clinical tags
      t.jsonb :custom_attributes, null: false, default: {}

      t.timestamps
    end

    add_index :appointments, :user_id, if_not_exists: true
    add_index :appointments, :contact_id, if_not_exists: true
    add_index :appointments, :start_time, if_not_exists: true
    add_index :appointments, :status, if_not_exists: true
    add_index :appointments, :category, if_not_exists: true
    add_index :appointments, :google_calendar_event_id, if_not_exists: true
    add_index :appointments, :custom_attributes, using: :gin, if_not_exists: true

    add_foreign_key :appointments, :users, column: :user_id, if_not_exists: true
    add_foreign_key :appointments, :contacts, column: :contact_id, if_not_exists: true
    add_foreign_key :appointments, :conversations, column: :conversation_id, if_not_exists: true
    add_foreign_key :appointments, :pipeline_items, column: :pipeline_item_id, if_not_exists: true

    add_check_constraint :appointments, "title != ''", name: 'appointments_title_not_empty', if_not_exists: true
  end
end
