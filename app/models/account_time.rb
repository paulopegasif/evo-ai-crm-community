# frozen_string_literal: true

# Single source of truth for the account's time zone. Calendar days (agenda,
# all-day appointments, dashboard buckets) are always computed in this zone,
# never in UTC or in the browser's zone.
module AccountTime
  DEFAULT_ZONE = 'America/Sao_Paulo'

  module_function

  def zone_name
    name = ENV.fetch('ACCOUNT_TIMEZONE', nil).presence || GlobalConfigService.load('ACCOUNT_TIMEZONE', nil).presence
    ActiveSupport::TimeZone[name.to_s] ? name : DEFAULT_ZONE
  rescue StandardError
    DEFAULT_ZONE
  end

  def zone
    ActiveSupport::TimeZone[zone_name]
  end

  # Start and end of a calendar day ("YYYY-MM-DD" or Date) in the account zone.
  def day_bounds(day)
    date = day.is_a?(Date) ? day : Date.iso8601(day.to_s)
    start = zone.local(date.year, date.month, date.day)
    [start, start.end_of_day.change(usec: 0)]
  end
end
