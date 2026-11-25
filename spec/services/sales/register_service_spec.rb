# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Sales::RegisterService do
  include SalesFixtures

  let(:user) { create_user('Agente') }
  let(:contact) { create_contact }
  let(:conversation) { create_conversation(contact: contact) }

  before { Current.reset }

  def register(attrs)
    described_class.new(attributes: attrs, user: user).call
  end

  it 'registra venda só com o valor, ligada à conversa e ao contato' do
    sale = register(amount: '350.00', conversation_id: conversation.id)
    expect(sale).to be_persisted
    expect(sale.amount).to eq(350)
    expect(sale.contact_id).to eq(contact.id)
    expect(sale.seller_id).to eq(user.id)
    expect(sale.created_by_id).to eq(user.id)
    expect(sale.pipeline_item_id).to be_nil
  end

  it 'recusa valor zero' do
    expect { register(amount: 0, conversation_id: conversation.id) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  context 'com card aberto em pipeline de vendas' do
    let!(:setup) { create_sales_pipeline(user: user) }
    let(:stages) { setup[1] }
    let!(:card) do
      PipelineItem.create!(pipeline: setup[0], pipeline_stage: stages[:proposal], conversation: conversation,
                           custom_fields: { 'value' => '999' })
    end

    it 'move o card para o estágio ganho, liga a venda e não gera venda duplicada' do
      expect { register(amount: 350, conversation_id: conversation.id) }.to change(Sale, :count).by(1)
      expect(card.reload.pipeline_stage).to eq(stages[:won])
      expect(Sale.last.pipeline_item_id).to eq(card.id)
      expect(Sale.last.amount).to eq(350)
    end

    it 'encontra card por contato quando o card é de outra conversa do contato' do
      other_conversation = create_conversation(contact: contact)
      register(amount: 10, conversation_id: other_conversation.id)
      expect(card.reload.pipeline_stage).to eq(stages[:won])
    end
  end
end
