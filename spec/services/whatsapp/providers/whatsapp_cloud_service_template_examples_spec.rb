# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Providers::WhatsappCloudService do
  let(:whatsapp_channel) do
    instance_double(Channel::Whatsapp, provider_config: { 'api_key' => 'api-token', 'phone_number_id' => '12345' })
  end
  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  describe '#process_template_components' do
    let(:body) { { 'type' => 'BODY', 'text' => 'Olá {{1}}, seu horário está confirmado para {{2}}.' } }

    it 'sends one example per body variable, using the form examples' do
      variables = [{ 'name' => '1', 'example' => 'Maria' }, { 'name' => '2', 'example' => '30/10 às 14h' }]

      result = service.send(:process_template_components, [body], variables)

      expect(result.first['example']).to eq('body_text' => [['Maria', '30/10 às 14h']])
    end

    it 'falls back to a placeholder per variable when no example is given' do
      result = service.send(:process_template_components, [body])

      expect(result.first['example']).to eq('body_text' => [['Exemplo 1', 'Exemplo 2']])
    end

    it 'uses the header variable example' do
      header = { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Pedido {{1}}' }

      result = service.send(:process_template_components, [header], [{ name: '1', example: '#123' }])

      expect(result.first['example']).to eq('header_text' => ['#123'])
    end

    it 'leaves bodies without variables untouched' do
      result = service.send(:process_template_components, [{ 'type' => 'BODY', 'text' => 'Olá!' }])

      expect(result.first).not_to have_key('example')
    end
  end
end
