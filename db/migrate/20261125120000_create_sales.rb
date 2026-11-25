class CreateSales < ActiveRecord::Migration[7.1]
  def change
    create_table :sales, id: :uuid do |t|
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.datetime :sold_at, null: false
      t.string :status, null: false, default: 'active'
      t.string :source, null: false, default: 'manual'
      t.boolean :missing_amount, null: false, default: false
      t.uuid :seller_id
      t.uuid :created_by_id
      t.uuid :contact_id
      t.uuid :conversation_id
      t.uuid :pipeline_item_id
      t.uuid :product_id
      t.text :notes
      t.datetime :cancelled_at
      t.timestamps
    end

    add_index :sales, %i[status sold_at]
    add_index :sales, %i[seller_id sold_at]
    add_index :sales, :contact_id
    add_index :sales, :conversation_id
    add_index :sales, :pipeline_item_id, unique: true, where: "status = 'active' AND pipeline_item_id IS NOT NULL",
                                         name: 'idx_sales_one_active_per_pipeline_item'
  end
end
