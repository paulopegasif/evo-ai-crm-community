# frozen_string_literal: true

class Assistant::V1::CustomersController < Assistant::V1::BaseController
  def search
    results = queries.search(params[:q])
    render_data({ query: params[:q].to_s, matches: results.size, customers: results })
  end

  def history
    render_data(queries.history(params[:id]))
  end

  def ranking
    scoped_period = params.slice(:period, :days, :from, :to).values.any?(&:present?) ? period : nil
    render_data({ kind: params[:kind].to_s, customers: queries.ranking(params[:kind], limit: params[:limit] || 10,
                                                                                      period: scoped_period) },
                period: scoped_period)
  end

  private

  def queries
    @queries ||= BusinessAssistant::Queries::Customers.new
  end
end
