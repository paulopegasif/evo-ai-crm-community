# frozen_string_literal: true

class DailySummary::SendJob < ApplicationJob
  queue_as :scheduled_jobs

  # Evita dois envios simultâneos do mesmo dia (scheduler disparando em sequência).
  def perform(date_iso)
    date = Date.iso8601(date_iso)
    lock_key = "daily_summary:lock:#{date_iso}"
    return unless Redis::Alfred.set(lock_key, '1', nx: true, ex: 10.minutes.to_i)

    begin
      settings = DailySummary::Settings.load
      return unless settings.due?

      DailySummary::Sender.new(settings: settings, date: date).call
    ensure
      Redis::Alfred.delete(lock_key)
    end
  end
end
