# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Sales::BackfillService do
  include SalesFixtures

  let(:user) { create_user('Dono') }
  let!(:setup) { create_sales_pipeline(user: user) }
  let(:stages) { setup[1] }
  let!(:won_card) do
    card = PipelineItem.create!(pipeline: setup[0], pipeline_stage: stages[:proposal], contact: create_contact,
                                custom_fields: { 'value' => '700' })
    card.move_to_stage(stages[:won])
    Sale.where(pipeline_item: card).delete_all # simula card ganho antes do recurso existir
    card
  end

  it 'não grava em simulação' do
    result = nil
    expect { result = described_class.new(dry_run: true).call }.not_to change(Sale, :count)
    expect(result.created).to eq(1)
    expect(result.total_amount).to eq(700)
  end

  it 'grava com a data do movimento para o estágio ganho e é idempotente' do
    movement_at = won_card.stage_movements.where(to_stage_id: stages[:won].id).maximum(:created_at)
    described_class.new(dry_run: false).call
    sale = Sale.find_by(pipeline_item: won_card)
    expect(sale.sold_at).to be_within(1.second).of(movement_at)
    expect(described_class.new(dry_run: false).call.created).to eq(0)
  end
end
