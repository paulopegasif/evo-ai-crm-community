# frozen_string_literal: true

class Assistant::V1::LeadsController < Assistant::V1::BaseController
  def funnel
    render_data(BusinessAssistant::Queries::Leads.new(period(default: 'last_30_days')).funnel,
                period: period, coverage: BusinessAssistant::Coverage.for_period(period))
  end
end
