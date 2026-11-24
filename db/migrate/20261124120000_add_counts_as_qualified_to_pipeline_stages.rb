# frozen_string_literal: true

# Stages flagged here count as "qualified lead" for the Tracking funnel and send
# the Conversions API QualifiedLead event. Same column the client/lumom tracking
# revamp (20261104120000) adds; guarded so either migration can run first.
class AddCountsAsQualifiedToPipelineStages < ActiveRecord::Migration[7.1]
  def up
    return if column_exists?(:pipeline_stages, :counts_as_qualified)

    add_column :pipeline_stages, :counts_as_qualified, :boolean, default: false, null: false
  end

  def down
    remove_column :pipeline_stages, :counts_as_qualified if column_exists?(:pipeline_stages, :counts_as_qualified)
  end
end
