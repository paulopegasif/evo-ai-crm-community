# frozen_string_literal: true

class Assistant::V1::SalesController < Assistant::V1::BaseController
  def summary
    render_data(BusinessAssistant::Queries::SalesReport.new(period).summary,
                period: period, coverage: BusinessAssistant::Coverage.for_period(period))
  end
end
