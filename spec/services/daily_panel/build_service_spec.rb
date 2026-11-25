# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe DailyPanel::BuildService do
  include SalesFixtures

  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:today) { Date.new(2026, 11, 25) }
  let(:admin) { create_user('Paulo Henrique') }
  let(:ana) { create_user('Ana') }

  before do
    allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo')
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('DAILY_QUOTE_DEFAULT_CATEGORY').and_return('negocios')
  end

  def at(date, hour = 10)
    zone.local(date.year, date.month, date.day, hour)
  end

  def build(user:, admin_flag:)
    described_class.new(user: user, admin: admin_flag, today: today).call
  end

  it 'soma vendas de hoje, ontem e do mesmo dia da semana anterior' do
    create_sale(amount: 1000, sold_at: at(today))
    create_sale(amount: 240, sold_at: at(today, 22))
    create_sale(amount: 800, sold_at: at(today - 1))
    create_sale(amount: 50, sold_at: at(today - 7))
    create_sale(amount: 999, sold_at: at(today)).cancel!

    data = build(user: admin, admin_flag: true)
    expect(data[:sales][:today]).to eq(count: 2, amount: 1240.0)
    expect(data[:sales][:yesterday]).to eq(count: 1, amount: 800.0)
    expect(data[:sales][:same_weekday_last_week]).to eq(count: 1, amount: 50.0)
    expect(data[:no_sales_hint]).to be_nil
    expect(data[:user]).to eq(first_name: 'Paulo', is_admin: true)
    expect(data[:quote][:category]).to eq('negocios')
  end

  it 'agente vê só as próprias vendas e a própria meta' do
    create_sale(amount: 300, seller: ana, sold_at: at(today))
    create_sale(amount: 700, seller: admin, sold_at: at(today))
    SalesGoal.create!(month: today, amount: 5000, user: ana)
    SalesGoal.create!(month: today, amount: 50_000)

    data = build(user: ana, admin_flag: false)
    expect(data[:sales][:today][:amount]).to eq(300.0)
    expect(data[:month]).to include(goal: 5000.0, sold: 300.0, scope: 'mine')
  end

  it 'admin vê a meta geral do mês' do
    SalesGoal.create!(month: today, amount: 20_000)
    create_sale(amount: 12_400, sold_at: at(today - 10))
    data = build(user: admin, admin_flag: true)
    expect(data[:month]).to include(goal: 20_000.0, percent: 62.0, remaining: 7600.0, days_left: 6, month: '2026-11')
  end

  it 'sem vendas hoje traz a dica com propostas paradas' do
    _, stages = create_sales_pipeline(user: admin)
    card = PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:proposal], contact: create_contact)
    card.update_columns(entered_at: 5.days.ago, created_at: 5.days.ago)
    card.stage_movements.update_all(created_at: 5.days.ago)
    PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:new], contact: create_contact)

    data = build(user: admin, admin_flag: true)
    expect(data[:todo][:stalled_items]).to eq(1)
    expect(data[:no_sales_hint]).to include(stalled_items: 1)
  end

  it 'conta vendas sem valor e follow-ups vencidos' do
    _, stages = create_sales_pipeline(user: admin)
    card = PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:proposal], contact: create_contact)
    card.move_to_stage(stages[:won])
    PipelineTask.create!(pipeline_item: card, title: 'Ligar', task_type: :follow_up, due_date: 2.days.ago,
                         created_by: admin, assigned_to: admin)

    data = build(user: admin, admin_flag: true)
    expect(data[:todo][:sales_missing_amount]).to eq(1)
    expect(data[:todo][:overdue_follow_ups]).to eq(1)
  end
end
