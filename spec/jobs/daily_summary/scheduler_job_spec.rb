# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailySummary::SchedulerJob do
  include ActiveJob::TestHelper

  it 'enfileira o envio quando está no horário' do
    allow(DailySummary::Settings).to receive(:load).and_return(instance_double(DailySummary::Settings, due?: true))
    expect { described_class.perform_now }.to have_enqueued_job(DailySummary::SendJob)
  end

  it 'não enfileira fora do horário' do
    allow(DailySummary::Settings).to receive(:load).and_return(instance_double(DailySummary::Settings, due?: false))
    expect { described_class.perform_now }.not_to have_enqueued_job(DailySummary::SendJob)
  end
end

RSpec.describe DailySummary::SendJob do
  it 'não envia duas vezes em paralelo para o mesmo dia' do
    allow(DailySummary::Settings).to receive(:load).and_return(instance_double(DailySummary::Settings, due?: true))
    sender = instance_double(DailySummary::Sender, call: { sent: 1, failed: [] })
    allow(DailySummary::Sender).to receive(:new).and_return(sender)
    Redis::Alfred.set('daily_summary:lock:2026-11-25', '1', nx: true, ex: 60)

    described_class.perform_now('2026-11-25')
    expect(sender).not_to have_received(:call)
  ensure
    Redis::Alfred.delete('daily_summary:lock:2026-11-25')
  end

  it 'envia quando livre e está no horário' do
    allow(DailySummary::Settings).to receive(:load).and_return(instance_double(DailySummary::Settings, due?: true))
    sender = instance_double(DailySummary::Sender, call: { sent: 1, failed: [] })
    allow(DailySummary::Sender).to receive(:new).and_return(sender)
    Redis::Alfred.delete('daily_summary:lock:2026-11-25')

    described_class.perform_now('2026-11-25')
    expect(sender).to have_received(:call)
  end
end
