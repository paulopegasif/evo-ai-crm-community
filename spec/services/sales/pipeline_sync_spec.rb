# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Sales::PipelineSync do
  include SalesFixtures

  let(:user) { create_user('Dono') }
  let(:contact) { create_contact }

  before { Current.reset }

  def card_in(pipeline, stage, value: nil)
    custom = value ? { 'value' => value.to_s } : {}
    PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage, contact: contact, custom_fields: custom)
  end

  context 'com pipeline de vendas' do
    let!(:setup) { create_sales_pipeline(user: user) }
    let(:pipeline) { setup[0] }
    let(:stages) { setup[1] }

    it 'cria venda automática ao arrastar card para estágio ganho' do
      card = PipelineItem.create!(pipeline: pipeline, pipeline_stage: stages[:proposal], contact: contact,
                                  custom_fields: { 'services' => [{ 'name' => 'Implantação', 'value' => '1200' }] })
      expect { card.move_to_stage(stages[:won]) }.to change(Sale.active, :count).by(1)
      sale = Sale.last
      expect(sale.amount).to eq(1200)
      expect(sale.source).to eq('pipeline')
      expect(sale.pipeline_item).to eq(card)
      expect(sale.contact_id).to eq(contact.id)
    end

    it 'cria venda quando o card nasce em estágio ganho, usando custom_fields value' do
      expect { card_in(pipeline, stages[:won], value: 300) }.to change(Sale.active, :count).by(1)
      expect(Sale.last.amount).to eq(300)
    end

    it 'marca venda sem valor quando o card não tem valor' do
      card = card_in(pipeline, stages[:proposal])
      card.move_to_stage(stages[:won])
      expect(Sale.last.missing_amount).to be(true)
    end

    it 'cancela só a venda automática ao reabrir o card' do
      card = card_in(pipeline, stages[:proposal], value: 500)
      card.move_to_stage(stages[:won])
      manual = create_sale(amount: 80, contact: contact)
      card.move_to_stage(stages[:proposal])
      expect(Sale.where(pipeline_item: card).pluck(:status)).to eq(['cancelled'])
      expect(manual.reload.status).to eq('active')
    end

    it 'não duplica venda quando já existe venda ativa ligada ao card' do
      card = card_in(pipeline, stages[:proposal], value: 500)
      create_sale(amount: 500, pipeline_item: card)
      expect { card.move_to_stage(stages[:won]) }.not_to change(Sale, :count)
    end

    it 'usa o responsável da conversa como vendedor' do
      seller = create_user('Ana')
      conversation = create_conversation(contact: contact, assignee: seller)
      card = PipelineItem.create!(pipeline: pipeline, pipeline_stage: stages[:proposal], conversation: conversation,
                                  custom_fields: { 'value' => '90' })
      card.move_to_stage(stages[:won])
      expect(Sale.last.seller_id).to eq(seller.id)
    end
  end

  it 'ignora pipeline de suporte' do
    pipeline, stages = create_sales_pipeline(user: user, type: 'support')
    card = card_in(pipeline, stages[:proposal], value: 100)
    expect { card.move_to_stage(stages[:won]) }.not_to change(Sale, :count)
  end
end
