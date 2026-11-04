# frozen_string_literal: true

class TrackingAndCalendarRevamp < ActiveRecord::Migration[7.1]
  def change
    # Appointments whose source only knows the day ("Horário a definir").
    add_column :appointments, :all_day, :boolean, default: false, null: false

    # Pipeline stages that mark a lead as qualified in Lead Tracking.
    add_column :pipeline_stages, :counts_as_qualified, :boolean, default: false, null: false

    # Sales from an external CRM that could not be tied to a lead (review queue).
    create_table :external_unlinked_sales, id: :uuid do |t|
      t.string :source, limit: 100, null: false
      t.string :external_id, limit: 255, null: false
      t.string :customer_name, null: false
      t.string :customer_phone
      t.string :reason, limit: 50, null: false
      t.string :status, limit: 50, null: false, default: 'pending'
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.string :category, limit: 100
      t.datetime :sold_at
      t.jsonb :candidate_contact_ids, null: false, default: []
      t.jsonb :payload, null: false, default: {}
      t.uuid :resolved_contact_id
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :external_unlinked_sales, %i[source external_id], unique: true
    add_index :external_unlinked_sales, :status
    add_index :external_unlinked_sales, :sold_at
  end
end
