# frozen_string_literal: true

class Assistant::V1::PendingController < Assistant::V1::BaseController
  def show
    render_data(BusinessAssistant::Queries::Pending.new.call)
  end
end
