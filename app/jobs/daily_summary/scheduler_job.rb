# frozen_string_literal: true

# Roda a cada 5 minutos (config/schedule.yml): dispara o envio do resumo quando chegou o horário.
class DailySummary::SchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    settings = DailySummary::Settings.load
    return unless settings.due?

    DailySummary::SendJob.perform_later(Sales::TimeZone.today.iso8601)
  end
end
