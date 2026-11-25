class CreateSalesGoals < ActiveRecord::Migration[7.1]
  def change
    create_table :sales_goals, id: :uuid do |t|
      t.date :month, null: false
      t.uuid :user_id
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
    end

    add_index :sales_goals, %i[month user_id], unique: true, where: 'user_id IS NOT NULL',
                                               name: 'idx_sales_goals_month_user'
    add_index :sales_goals, :month, unique: true, where: 'user_id IS NULL', name: 'idx_sales_goals_month_general'
  end
end
