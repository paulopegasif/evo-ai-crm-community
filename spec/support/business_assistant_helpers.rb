# frozen_string_literal: true

# Fixtures dos specs do assistente de negócio no WhatsApp.
module BusinessAssistantHelpers
  OWNER_PHONE = '+5562999990000'
  WEBHOOK_URL = 'https://n8n.test/webhook/assistente'
  SECRET = 's' * 40

  def assistant_inbox
    @assistant_inbox ||= Inbox.create!(name: 'Assistente', channel: Channel::Api.create!)
  end

  def stub_whatsapp_inboxes(*inboxes)
    inboxes = [assistant_inbox] if inboxes.empty?
    allow(DailySummary::Settings).to receive(:whatsapp_inboxes).and_return(Inbox.where(id: inboxes.map(&:id)))
  end

  def configure_assistant!(**overrides)
    stub_whatsapp_inboxes
    settings = BusinessAssistant::Settings.load.assign({
      enabled: true, inbox_id: assistant_inbox.id, webhook_url: WEBHOOK_URL, signing_secret: SECRET,
      phones: [{ phone: OWNER_PHONE, name: 'Carla', scope: 'owner' }]
    }.merge(overrides))
    raise settings.errors.full_messages.join(', ') unless settings.save

    BusinessAssistant::Settings.load
  end

  def assistant_conversation(phone = OWNER_PHONE, inbox: assistant_inbox)
    digits = BusinessAssistant::Settings.whatsapp_digits(phone)
    contact = Contact.find_by(phone_number: "+#{digits}") || Contact.create!(name: 'Carla', phone_number: "+#{digits}")
    contact_inbox = ContactInbox.create!(inbox: inbox, contact: contact, source_id: digits)
    Conversation.create!(inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def incoming_message(conversation, content = 'quanto vendi hoje?')
    conversation.messages.create!(content: content, message_type: :incoming, inbox_id: conversation.inbox_id,
                                  sender: conversation.contact)
  end

  # Cabeçalho com token temporário válido para a conversa do dono.
  def assistant_headers(settings = BusinessAssistant::Settings.load, conversation: assistant_conversation)
    DailySummary::Exclusion.mark_internal!(conversation, label: DailySummary::Exclusion::ASSISTANT_LABEL)
    issued = BusinessAssistant::Token.issue(settings: settings, phone_entry: settings.phones.first,
                                            conversation: conversation)
    { 'Authorization' => "Bearer #{issued[:token]}" }
  end

  def assistant_data
    response.parsed_body['data']
  end

  # Tabelas da integração Meta Ads (só existem nas branches de cliente); DDL é desfeito com a transação.
  def create_meta_ads_tables!
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      CREATE TABLE meta_ad_insights_daily (id bigserial PRIMARY KEY, meta_ad_id varchar NOT NULL,
        meta_campaign_id varchar, date date NOT NULL, spend numeric(14,2) NOT NULL DEFAULT 0,
        impressions bigint NOT NULL DEFAULT 0, reach bigint NOT NULL DEFAULT 0, clicks bigint NOT NULL DEFAULT 0,
        link_clicks bigint NOT NULL DEFAULT 0, conversations bigint NOT NULL DEFAULT 0,
        meta_leads bigint NOT NULL DEFAULT 0, currency varchar);
      CREATE TABLE meta_campaigns (id bigserial PRIMARY KEY, meta_id varchar NOT NULL, name varchar);
      CREATE TABLE meta_ads (id bigserial PRIMARY KEY, meta_id varchar NOT NULL, meta_campaign_id varchar, name varchar);
    SQL
  end

  def insert_insight(row)
    values = row.values_at(:ad, :campaign, :date, :spend).push(row.fetch(:leads, 0), row.fetch(:conversations, 0))
    sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, *values])
      INSERT INTO meta_ad_insights_daily (meta_ad_id, meta_campaign_id, date, spend, meta_leads, conversations, currency)
      VALUES (?, ?, ?, ?, ?, ?, 'BRL')
    SQL
    ActiveRecord::Base.connection.execute(sql)
  end

  def clear_assistant_redis!
    $alfred.with do |conn| # rubocop:disable Style/GlobalVars
      keys = conn.keys('business_assistant:*')
      conn.del(*keys) if keys.any?
    end
  end
end
