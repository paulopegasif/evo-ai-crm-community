# frozen_string_literal: true

class Assistant::V1::AdsController < Assistant::V1::BaseController
  def spend
    render_data(BusinessAssistant::Queries::Ads.new(period(default: 'last_7_days')).spend,
                period: period, coverage: BusinessAssistant::Coverage.for_period(period))
  end
end
