# frozen_string_literal: true

# Fixtures compartilhadas pelos specs do Painel do Dia (vendas, metas, resumo).
module SalesFixtures
  def create_user(name = 'Vendedor')
    User.create!(name: name, email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com")
  end

  def create_sales_pipeline(user:, type: 'sales')
    pipeline = Pipeline.create!(name: "Pipe #{SecureRandom.hex(3)}", pipeline_type: type, created_by: user)
    stages = {
      new: PipelineStage.create!(pipeline: pipeline, name: 'Novo', position: 1, stage_type: :active),
      proposal: PipelineStage.create!(pipeline: pipeline, name: 'Proposta', position: 2, stage_type: :active),
      won: PipelineStage.create!(pipeline: pipeline, name: 'Ganho', position: 3, stage_type: :completed),
      lost: PipelineStage.create!(pipeline: pipeline, name: 'Perdido', position: 4, stage_type: :cancelled)
    }
    [pipeline, stages]
  end

  def create_contact(name = 'Cliente')
    Contact.create!(name: name, email: "#{name.parameterize}-#{SecureRandom.hex(4)}@test.com")
  end

  def create_conversation(contact:, assignee: nil, inbox: nil)
    inbox ||= Inbox.create!(name: "API #{SecureRandom.hex(3)}", channel: Channel::Api.create!)
    contact_inbox = ContactInbox.create!(inbox: inbox, contact: contact, source_id: SecureRandom.hex(6))
    Conversation.create!(inbox: inbox, contact: contact, contact_inbox: contact_inbox, assignee: assignee)
  end

  def create_sale(amount:, seller: nil, sold_at: Time.current, **attrs)
    Sale.create!(amount: amount, seller: seller, sold_at: sold_at, source: attrs.delete(:source) || 'manual', **attrs)
  end
end

# Autenticação stubada contra o evo-auth para request specs (papel controla administrator?).
module SalesAuthHelpers
  AUTH_BASE_URL = 'http://auth.test'

  def with_auth_env
    original = ENV.fetch('EVO_AUTH_SERVICE_URL', nil)
    ENV['EVO_AUTH_SERVICE_URL'] = AUTH_BASE_URL
    Rails.cache.clear
    Current.reset
    yield
  ensure
    Rails.cache.clear
    Current.reset
    ENV['EVO_AUTH_SERVICE_URL'] = original
  end

  def auth_headers_for(user, role: 'agent')
    token = "token-#{user.id}"
    stub_request(:post, "#{AUTH_BASE_URL}/api/v1/auth/validate")
      .with(headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: 200,
                 body: { success: true, data: { user: { id: user.id, email: user.email, role: { key: role } } } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, %r{#{AUTH_BASE_URL}/api/v1/users/.+/check_permission}o)
      .to_return(status: 200, body: { success: true, data: { has_permission: false } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    { 'Authorization' => "Bearer #{token}" }
  end

  def json_data
    JSON.parse(response.body)['data']
  end
end
