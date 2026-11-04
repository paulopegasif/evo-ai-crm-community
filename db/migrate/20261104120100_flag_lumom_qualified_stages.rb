# frozen_string_literal: true

# Lumom's patient journey: an evaluation booked (stage 3) or anything after it,
# except lost, means the lead was qualified. Contact attempts and triage do not.
# No-op on other installations.
class FlagLumomQualifiedStages < ActiveRecord::Migration[7.1]
  LUMOM_PIPELINE_ID = '6ca4fb68-3146-495c-8710-f9ec60365daa'

  def up
    execute <<~SQL.squish
      UPDATE pipeline_stages SET counts_as_qualified = TRUE
      WHERE pipeline_id = '#{LUMOM_PIPELINE_ID}' AND stage_type <> 2 AND (position >= 3 OR name ~ '^[3-6][.]')
    SQL
  end

  def down
    execute "UPDATE pipeline_stages SET counts_as_qualified = FALSE WHERE pipeline_id = '#{LUMOM_PIPELINE_ID}'"
  end
end
