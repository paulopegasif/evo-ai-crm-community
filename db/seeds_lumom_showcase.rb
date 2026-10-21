# frozen_string_literal: true

puts "================================================================="
puts "  POPULANDO CRM LUMOM BEAUTY COM DADOS COMPLETOS PARA SHOWCASE  "
puts "================================================================="

# 1. USUÁRIOS E EQUIPE CLÍNICA
puts "\n[1/6] Configurando equipe clínica Lumom Beauty..."
admin_user = User.find_by(email: 'ifsul.ph@gmail.com') || User.first
raise "Nenhum usuário admin encontrado!" unless admin_user

admin_user.update!(
  name: 'Paulo Silva',
  display_name: 'Paulo Silva (Diretor Clínico)'
)

team_members_data = [
  {
    name: 'Dra. Camila Santos',
    display_name: 'Dra. Camila Santos (Biomédica Esteta)',
    email: 'camila@lumombeauty.com.br'
  },
  {
    name: 'Dr. Lucas Rocha',
    display_name: 'Dr. Lucas Rocha (Cirurgião / Harmonizador)',
    email: 'lucas@lumombeauty.com.br'
  },
  {
    name: 'Dra. Mariana Costa',
    display_name: 'Dra. Mariana Costa (Dermatologia & Laser)',
    email: 'mariana.costa@lumombeauty.com.br'
  },
  {
    name: 'Amanda Souza',
    display_name: 'Amanda Souza (Concierge & Recepção)',
    email: 'atendimento@lumombeauty.com.br'
  }
]

created_users = [admin_user]
team_members_data.each do |member|
  user = User.find_or_initialize_by(email: member[:email])
  user.uid = member[:email]
  user.name = member[:name]
  user.display_name = member[:display_name]
  user.confirmed_at = Time.current
  user.save!
  created_users << user
  puts "  ✓ Profissional: #{user.name} (#{user.email})"
end

# 2. GOOGLE CALENDAR INTEGRATION HOOK
puts "\n[2/6] Configurando integração ativa do Google Calendar..."
gcal_hook = Integrations::Hook.find_or_initialize_by(app_id: 'google_calendar')
gcal_hook.status = 1
gcal_hook.hook_type = 0
gcal_hook.settings = {
  'account_email' => 'agenda@lumombeauty.com.br',
  'calendar_id' => 'primary',
  'calendar_name' => 'Lumom Beauty - Consultas & Procedimentos',
  'sync_enabled' => true,
  'two_way_sync' => true,
  'sync_interval' => '5m',
  'auto_meet' => true,
  'reminder_minutes' => 60,
  'last_synced_at' => Time.current.iso8601,
  'total_events_synced' => 25
}
gcal_hook.save!
puts "  ✓ Integração Google Calendar ativada com sucesso para agenda@lumombeauty.com.br"

# 3. CANAIS E INBOXES DE ATENDIMENTO (WHATSAPP & WEBCHAT)
puts "\n[3/6] Configurando caixas de entrada e canais de atendimento..."
whatsapp_channel = Channel::Whatsapp.find_by(phone_number: '+5511987654321')
unless whatsapp_channel
  whatsapp_channel = Channel::Whatsapp.new(
    phone_number: '+5511987654321',
    provider: 'default',
    provider_config: { 'api_key' => 'mock_evo_key_lumom' },
    provider_connection: { 'status' => 'connected' }
  )
  whatsapp_channel.save(validate: false)
end

whatsapp_inbox = Inbox.find_or_create_by!(channel: whatsapp_channel) do |i|
  i.name = 'WhatsApp Oficial Lumom Beauty'
  i.enable_auto_assignment = true
  i.timezone = 'America/Sao_Paulo'
  i.business_name = 'Lumom Beauty'
  i.display_name = 'Atendimento Concierge'
end

# Associar equipe à caixa de entrada
created_users.each do |u|
  InboxMember.find_or_create_by!(inbox: whatsapp_inbox, user: u)
end
puts "  ✓ Caixa WhatsApp criada com #{created_users.count} membros atribuídos."

# 4. CONTATOS E PACIENTES RICOS (20 PACIENTES)
puts "\n[4/6] Cadastrando base de pacientes e leads com atribuição UTM..."
patients_data = [
  {
    name: 'Juliana Mendes',
    email: 'juliana.mendes@gmail.com',
    phone: '+5511987654321',
    source: 'instagram',
    medium: 'stories',
    campaign: 'harmonizacao-abril',
    tags: ['Harmonização', 'VIP', 'Lead Quente']
  },
  {
    name: 'Mariana Costa',
    email: 'mariana.costa@hotmail.com',
    phone: '+5511976543210',
    source: 'google_ads',
    medium: 'cpc',
    campaign: 'botox-preventivo',
    tags: ['Botox Preventivo', 'Avaliação Agendada']
  },
  {
    name: 'Carolina Ferreira',
    email: 'carol.ferreira@outlook.com',
    phone: '+5511965432109',
    source: 'instagram',
    medium: 'reels',
    campaign: 'harmonizacao-abril',
    tags: ['Harmonização', 'Lábios']
  },
  {
    name: 'Beatriz Santos',
    email: 'beatriz.santos@gmail.com',
    phone: '+5511954321098',
    source: 'indicacao',
    medium: 'amiga',
    campaign: 'boca-a-boca',
    tags: ['Bioestimulador', 'Indicação VIP']
  },
  {
    name: 'Fernanda Lima',
    email: 'fernanda.lima@uol.com.br',
    phone: '+5511943210987',
    source: 'tiktok',
    medium: 'video_viral',
    campaign: 'limpeza-pele-glow',
    tags: ['Limpeza de Pele', 'Glow']
  },
  {
    name: 'Renata Oliveira',
    email: 'renata.oliveira@gmail.com',
    phone: '+5511932109876',
    source: 'facebook_ads',
    medium: 'feed',
    campaign: 'bioestimulador-firmeza',
    tags: ['Laser & Luz Pulsada', 'Manchas']
  },
  {
    name: 'Amanda Rocha',
    email: 'amanda.rocha@gmail.com',
    phone: '+5511921098765',
    source: 'google_ads',
    medium: 'cpc',
    campaign: 'laser-manchas',
    tags: ['Laser', 'Melasma']
  },
  {
    name: 'Larissa Guimarães',
    email: 'larissa.guimaraes@yahoo.com',
    phone: '+5511910987654',
    source: 'instagram',
    medium: 'bio',
    campaign: 'avaliacao-gratuita',
    tags: ['Avaliação Facial', 'Novo Contato']
  },
  {
    name: 'Patrícia Albuquerque',
    email: 'patricia.albuquerque@gmail.com',
    phone: '+5511999887766',
    source: 'instagram',
    medium: 'feed',
    campaign: 'harmonizacao-abril',
    tags: ['Harmonização', 'Malar & Mandíbula']
  },
  {
    name: 'Gabriela Vasconcelos',
    email: 'gabi.vasconcelos@hotmail.com',
    phone: '+5511988776655',
    source: 'google_ads',
    medium: 'search',
    campaign: 'botox-preventivo',
    tags: ['Botox Preventivo', 'Testa & Glabela']
  },
  {
    name: 'Vanessa Silveira',
    email: 'vanessa.silveira@globo.com',
    phone: '+5511977665544',
    source: 'tiktok',
    medium: 'influencer',
    campaign: 'limpeza-pele-glow',
    tags: ['Limpeza de Pele', 'Hidratação']
  },
  {
    name: 'Camila Duarte',
    email: 'camila.duarte@gmail.com',
    phone: '+5511966554433',
    source: 'indicacao',
    medium: 'paciente_antigo',
    campaign: 'boca-a-boca',
    tags: ['Bioestimulador', 'Sculptra']
  },
  {
    name: 'Tatiana Ribeiro',
    email: 'tatiana.ribeiro@uol.com.br',
    phone: '+5511955443322',
    source: 'facebook_ads',
    medium: 'carrossel',
    campaign: 'bioestimulador-firmeza',
    tags: ['Radiesse', 'Pescoço & Colo']
  },
  {
    name: 'Bruna Medeiros',
    email: 'bruna.medeiros@gmail.com',
    phone: '+5511944332211',
    source: 'google_ads',
    medium: 'maps',
    campaign: 'clinica-estetica-sp',
    tags: ['Avaliação Geral', 'Alta Renda']
  },
  {
    name: 'Isabela Fontes',
    email: 'isabela.fontes@gmail.com',
    phone: '+5511933221100',
    source: 'instagram',
    medium: 'stories',
    campaign: 'harmonizacao-abril',
    tags: ['Rinomodelação', 'Harmonização']
  },
  {
    name: 'Daniela Nogueira',
    email: 'daniela.nogueira@terra.com.br',
    phone: '+5511922110099',
    source: 'indicacao',
    medium: 'dra_camila',
    campaign: 'boca-a-boca',
    tags: ['Harmonização', 'VIP']
  },
  {
    name: 'Sofia Ramalho',
    email: 'sofia.ramalho@gmail.com',
    phone: '+5511911009988',
    source: 'tiktok',
    medium: 'parceria',
    campaign: 'limpeza-pele-glow',
    tags: ['Limpeza de Pele', 'Jovem']
  },
  {
    name: 'Letícia Pires',
    email: 'leticia.pires@outlook.com',
    phone: '+5511900998877',
    source: 'google_ads',
    medium: 'cpc',
    campaign: 'laser-manchas',
    tags: ['Laser Lavieen', 'Rejuvenescimento']
  }
]

created_contacts = []
patients_data.each do |p|
  contact = Contact.find_or_initialize_by(email: p[:email])
  contact.name = p[:name]
  contact.phone_number = p[:phone]
  contact.custom_attributes = {
    'utm_source' => p[:source],
    'utm_medium' => p[:medium],
    'utm_campaign' => p[:campaign],
    'channel' => p[:source].capitalize,
    'tags' => p[:tags]
  }
  contact.save!
  created_contacts << contact
end
puts "  ✓ #{created_contacts.count} pacientes cadastrados com sucesso."

# 5. PIPELINE E CRM FUNIL (KANBAN)
puts "\n[5/6] Configurando Pipeline de Vendas 'Jornada do Paciente - Lumom Beauty'..."
pipeline = Pipeline.find_or_create_by!(name: 'Jornada do Paciente - Lumom Beauty') do |pipe|
  pipe.description = 'Funil comercial completo da Lumom Beauty, desde a captura do lead até o procedimento realizado.'
  pipe.pipeline_type = 'sales'
  pipe.visibility = :public
  pipe.is_default = true
  pipe.is_active = true
  pipe.created_by = admin_user
end

stages_config = [
  { name: '1. Novos Leads (Meta / Google / TikTok)', color: '#3B82F6', type: :active },
  { name: '2. Contato Inicial & Triagem', color: '#F59E0B', type: :active },
  { name: '3. Avaliação Agendada', color: '#8B5CF6', type: :active },
  { name: '4. Compareceu & Plano Apresentado', color: '#EC4899', type: :active },
  { name: '5. Fechado & Procedimento Realizado', color: '#10B981', type: :completed },
  { name: '6. Pós-Procedimento & Retorno', color: '#06B6D4', type: :active }
]

stages = []
stages_config.each_with_index do |sc, idx|
  stage = PipelineStage.find_or_initialize_by(pipeline: pipeline, name: sc[:name])
  stage.position = idx + 1
  stage.color = sc[:color]
  stage.stage_type = sc[:type]
  stage.save!
  stages << stage
  puts "  ✓ Etapa #{idx + 1}: #{stage.name}"
end

# Distribuir pacientes nas etapas do Pipeline
PipelineItem.where(pipeline: pipeline).destroy_all

deal_distribution = [
  # Etapa 0: Novos Leads
  { contact_idx: 7, stage_idx: 0, val: 450, notes: 'Lead vindo do Instagram Bio - Avaliação' },
  { contact_idx: 13, stage_idx: 0, val: 650, notes: 'Lead vindo do Google Maps' },
  { contact_idx: 16, stage_idx: 0, val: 350, notes: 'Lead vindo de Parceria TikTok' },

  # Etapa 1: Contato Inicial & Triagem
  { contact_idx: 6, stage_idx: 1, val: 1800, notes: 'Laser manchas - Atendente Amanda em conversa' },
  { contact_idx: 10, stage_idx: 1, val: 350, notes: 'Limpeza de pele glow - agendando horário' },
  { contact_idx: 17, stage_idx: 1, val: 2400, notes: 'Interesse em Laser Lavieen' },

  # Etapa 2: Avaliação Agendada
  { contact_idx: 1, stage_idx: 2, val: 1200, notes: 'Botox preventivo agendado com Dra. Mariana' },
  { contact_idx: 8, stage_idx: 2, val: 3500, notes: 'Avaliação Harmonização com Dra. Camila' },
  { contact_idx: 9, stage_idx: 2, val: 1300, notes: 'Botox agendado com Dr. Lucas' },
  { contact_idx: 14, stage_idx: 2, val: 3200, notes: 'Rinomodelação agendada com Dr. Lucas' },

  # Etapa 3: Compareceu & Plano Apresentado
  { contact_idx: 2, stage_idx: 3, val: 2800, notes: 'Harmonização labial e malar - proposta enviada' },
  { contact_idx: 11, stage_idx: 3, val: 3800, notes: 'Sculptra 2 frascos - aguardando aprovação cartão' },
  { contact_idx: 12, stage_idx: 3, val: 2600, notes: 'Radiesse pescoço e colo' },

  # Etapa 4: Fechado & Procedimento Realizado
  { contact_idx: 0, stage_idx: 4, val: 3200, notes: 'Harmonização facial completa realizada com Dra. Camila!' },
  { contact_idx: 3, stage_idx: 4, val: 2900, notes: 'Bioestimulador de colágeno aplicado - Pago à vista PIX' },
  { contact_idx: 4, stage_idx: 4, val: 350, notes: 'Limpeza de pele profunda glow realizada' },
  { contact_idx: 15, stage_idx: 4, val: 4200, notes: 'Plano VIP Harmonização Fechado' },

  # Etapa 5: Pós-Procedimento & Retorno
  { contact_idx: 5, stage_idx: 5, val: 1800, notes: 'Sessão 1 de Laser realizada, retorno em 21 dias' }
]

deal_distribution.each do |deal|
  contact = created_contacts[deal[:contact_idx]]
  stage = stages[deal[:stage_idx]]
  next unless contact && stage

  PipelineItem.create!(
    pipeline: pipeline,
    pipeline_stage: stage,
    contact: contact,
    conversation_id: nil,
    assigned_by: created_users.sample,
    custom_fields: {
      'deal_value' => deal[:val],
      'procedure_interest' => contact.custom_attributes['tags']&.first || 'Estética',
      'notes' => deal[:notes]
    }
  )
end
puts "  ✓ #{deal_distribution.count} negociações/deals distribuídos no Kanban de Vendas."

# 6. MENSAGENS E CONVERSAS REAIS NO WHATSAPP
puts "\n[6/6] Criando conversas e mensagens no WhatsApp Lumom Beauty..."
Conversation.destroy_all
Message.destroy_all

chat_scenarios = [
  {
    contact: created_contacts[0], # Juliana Mendes
    user: created_users[1], # Dra. Camila
    messages: [
      { from: :contact, text: "Olá! Boa tarde, tudo bem? Vi o vídeo de antes e depois da Harmonização no Instagram e fiquei encantada! Vocês atendem em Moema?", time: 3.hours.ago },
      { from: :user, text: "Olá Juliana, tudo ótimo por aqui! Seja muito bem-vinda à Lumom Beauty! ✨ Sim, nossa clínica fica no coração de Moema, com estacionamento privativo e todo o conforto.", time: 2.hours.ago + 50.minutes },
      { from: :contact, text: "Que maravilha! Queria muito fazer uma avaliação para alinhar o contorno da mandíbula e lábios. Como funciona?", time: 2.hours.ago + 40.minutes },
      { from: :user, text: "Nossa avaliação com a Dra. Camila é completa: fazemos mapeamento facial 3D e planejamos a volumetria ideal de acordo com a harmonia do seu rosto. Temos horários disponíveis nesta quinta às 14h ou sexta às 11h. Qual fica melhor para você?", time: 2.hours.ago + 20.minutes },
      { from: :contact, text: "Quinta às 14h é excelente! Pode confirmar por favor?", time: 2.hours.ago },
      { from: :user, text: "Perfeito, Juliana! Consulta agendada com sucesso com a Dra. Camila Santos. Já sincronizei com nosso Google Calendar e te enviei as orientações prévias. Te esperamos!", time: 1.hour.ago }
    ]
  },
  {
    contact: created_contacts[1], # Mariana Costa
    user: created_users[3], # Dra. Mariana Costa
    messages: [
      { from: :contact, text: "Bom dia! Gostaria de tirar uma dúvida sobre o Botox preventivo. A partir de qual idade é indicado?", time: 5.hours.ago },
      { from: :user, text: "Olá Mariana! Excelente pergunta! O Botox preventivo costuma ser muito indicado a partir dos 25 a 28 anos, quando as linhas dinâmicas começam a marcar suavemente.", time: 4.hours.ago + 30.minutes },
      { from: :contact, text: "Entendi! E o resultado fica artificial ou bem natural?", time: 4.hours.ago },
      { from: :user, text: "Na Lumom prezamos pela naturalidade absoluta: você mantém todas as suas expressões, apenas com ar descansado e prevenindo rugas fixas. Trabalhamos exclusivamente com marcas padrão ouro (Botox Allergan e Dysport).", time: 3.hours.ago + 45.minutes },
      { from: :contact, text: "Amei! Gostaria de agendar para a próxima semana com certeza.", time: 3.hours.ago }
    ]
  },
  {
    contact: created_contacts[3], # Beatriz Santos
    user: created_users[0], # Paulo Silva
    messages: [
      { from: :contact, text: "Oi Paulo! A Renata me indicou a clínica de vocês, disse que o resultado do Bioestimulador dela ficou impecável!", time: 6.hours.ago },
      { from: :user, text: "Oi Beatriz! Que prazer enorme receber sua mensagem! A Renata é uma querida e o resultado dela realmente ficou espetacular.", time: 5.hours.ago + 20.minutes },
      { from: :contact, text: "Vocês trabalham com Radiesse ou Sculptra? Tenho 38 anos e sinto que preciso estimular colágeno no terço médio.", time: 5.hours.ago },
      { from: :user, text: "Trabalhamos com os dois! Na avaliação decidimos qual molécula entrega o melhor vetor de tração e estímulo biológico para o seu tipo de pele. Já vou reservar um horário prioritário para você.", time: 4.hours.ago }
    ]
  }
]

chat_scenarios.each_with_index do |scenario, idx|
  contact = scenario[:contact]
  assigned_user = scenario[:user]

  contact_inbox = ContactInbox.find_or_create_by!(
    contact: contact,
    inbox: whatsapp_inbox
  ) do |ci|
    ci.source_id = contact.phone_number
  end

  conv = Conversation.create!(
    inbox: whatsapp_inbox,
    contact: contact,
    contact_inbox: contact_inbox,
    assignee: assigned_user,
    status: :open,
    display_id: idx + 1,
    uuid: SecureRandom.uuid,
    last_activity_at: Time.current,
    additional_attributes: { 'browser': 'WhatsApp Mobile', 'ip': '189.120.45.10' }
  )

  scenario[:messages].each do |msg|
    sender = msg[:from] == :contact ? contact : assigned_user
    sender_type = msg[:from] == :contact ? 'Contact' : 'User'
    msg_type = msg[:from] == :contact ? :incoming : :outgoing

    Message.create!(
      conversation: conv,
      inbox: whatsapp_inbox,
      sender: sender,
      sender_type: sender_type,
      message_type: msg_type,
      content: msg[:text],
      created_at: msg[:time],
      updated_at: msg[:time]
    )
  end
  puts "  ✓ Conversa #{idx + 1} criada com #{contact.name} (#{scenario[:messages].count} mensagens)."
end

# 7. AGENDAMENTOS COMPLETOS (25 CONSULTAS COM SINCRONIA GOOGLE CALENDAR)
puts "\n[7/7] Gerando 25 agendamentos na agenda sincronizada..."
Appointment.destroy_all

appointment_templates = [
  # Amanda Rocha
  { contact_idx: 6, user_idx: 0, cat: 'Avaliação Facial', day: 16, hour: 11, min: 0, dur: 30, st: :attended, price: 100.0 },
  # Renata Oliveira
  { contact_idx: 5, user_idx: 2, cat: 'Laser & Luz Pulsada', day: 17, hour: 10, min: 30, dur: 60, st: :attended, price: 350.0 },
  # Beatriz Santos
  { contact_idx: 3, user_idx: 1, cat: 'Bioestimulador de Colágeno', day: 18, hour: 14, min: 0, dur: 60, st: :attended, price: 1500.0 },
  # Fernanda Lima
  { contact_idx: 4, user_idx: 0, cat: 'Avaliação Facial', day: 18, hour: 16, min: 0, dur: 30, st: :no_show, price: 0.0 },
  # Juliana Mendes
  { contact_idx: 0, user_idx: 1, cat: 'Harmonização Facial', day: 19, hour: 9, min: 0, dur: 90, st: :confirmed, price: 2800.0 },
  # Mariana Costa
  { contact_idx: 1, user_idx: 2, cat: 'Limpeza de Pele Profunda', day: 19, hour: 14, min: 0, dur: 75, st: :scheduled, price: 280.0 },
  # Carolina Ferreira
  { contact_idx: 2, user_idx: 1, cat: 'Toxina Botulínica (Botox)', day: 19, hour: 16, min: 0, dur: 45, st: :confirmed, price: 1200.0 },
  # Larissa Guimarães
  { contact_idx: 7, user_idx: 0, cat: 'Avaliação Facial', day: 20, hour: 10, min: 0, dur: 30, st: :scheduled, price: 100.0 },
  # Juliana Mendes (Retorno)
  { contact_idx: 0, user_idx: 1, cat: 'Retorno / Acompanhamento', day: 22, hour: 11, min: 30, dur: 30, st: :scheduled, price: 0.0 },

  # Próximos agendamentos
  # Patrícia Albuquerque
  { contact_idx: 8, user_idx: 1, cat: 'Harmonização Facial', day: 21, hour: 14, min: 0, dur: 90, st: :confirmed, price: 3500.0 },
  # Gabriela Vasconcelos
  { contact_idx: 9, user_idx: 2, cat: 'Toxina Botulínica (Botox)', day: 22, hour: 15, min: 0, dur: 45, st: :confirmed, price: 1300.0 },
  # Vanessa Silveira
  { contact_idx: 10, user_idx: 2, cat: 'Limpeza de Pele Profunda', day: 23, hour: 10, min: 0, dur: 75, st: :scheduled, price: 280.0 },
  # Camila Duarte
  { contact_idx: 11, user_idx: 1, cat: 'Bioestimulador de Colágeno', day: 23, hour: 14, min: 0, dur: 60, st: :confirmed, price: 3800.0 },
  # Tatiana Ribeiro
  { contact_idx: 12, user_idx: 1, cat: 'Bioestimulador de Colágeno', day: 24, hour: 11, min: 0, dur: 60, st: :scheduled, price: 2600.0 },
  # Bruna Medeiros
  { contact_idx: 13, user_idx: 0, cat: 'Avaliação Facial', day: 24, hour: 16, min: 0, dur: 30, st: :scheduled, price: 100.0 },
  # Isabela Fontes
  { contact_idx: 14, user_idx: 2, cat: 'Harmonização Facial', day: 26, hour: 9, min: 30, dur: 90, st: :confirmed, price: 3200.0 },
  # Daniela Nogueira
  { contact_idx: 15, user_idx: 1, cat: 'Harmonização Facial', day: 26, hour: 14, min: 0, dur: 90, st: :confirmed, price: 4200.0 },
  # Sofia Ramalho
  { contact_idx: 16, user_idx: 2, cat: 'Limpeza de Pele Profunda', day: 27, hour: 11, min: 0, dur: 75, st: :scheduled, price: 280.0 },
  # Letícia Pires
  { contact_idx: 17, user_idx: 3, cat: 'Laser & Luz Pulsada', day: 28, hour: 15, min: 0, dur: 60, st: :confirmed, price: 1800.0 },
  # Beatriz Santos (Retorno)
  { contact_idx: 3, user_idx: 1, cat: 'Retorno / Acompanhamento', day: 29, hour: 10, min: 0, dur: 30, st: :scheduled, price: 0.0 },
  # Mariana Costa (Botox)
  { contact_idx: 1, user_idx: 2, cat: 'Toxina Botulínica (Botox)', day: 29, hour: 14, min: 0, dur: 45, st: :scheduled, price: 1200.0 },
  # Amanda Rocha (Laser Sessão 2)
  { contact_idx: 6, user_idx: 3, cat: 'Laser & Luz Pulsada', day: 30, hour: 11, min: 0, dur: 60, st: :scheduled, price: 800.0 }
]

base_year = 2026
base_month = 10

appointment_templates.each do |at|
  contact = created_contacts[at[:contact_idx]]
  assigned_user = created_users[at[:user_idx]] || admin_user
  next unless contact

  start_t = Time.zone.local(base_year, base_month, at[:day], at[:hour], at[:min])
  end_t = start_t + at[:dur].minutes

  Appointment.create!(
    title: "#{at[:cat]} - #{contact.name}",
    description: "Consulta e atendimento de #{at[:cat]} para #{contact.name}. Paciente orientada sobre cuidados pré e pós-procedimento.",
    category: at[:cat],
    status: at[:st],
    start_time: start_t,
    end_time: end_t,
    duration_minutes: at[:dur],
    user: assigned_user,
    contact: contact,
    location: "Lumom Beauty - Consultório #{rand(1..3)} (Moema)",
    price: at[:price],
    google_calendar_event_id: "gcal_lumom_#{SecureRandom.hex(8)}",
    google_calendar_sync_status: 'synced',
    google_meet_link: at[:cat] == 'Avaliação Facial' ? "https://meet.google.com/lum-#{SecureRandom.hex(3)}-om" : nil,
    custom_attributes: {
      'professional_name' => assigned_user.name,
      'patient_phone' => contact.phone_number,
      'synced_at' => Time.current.iso8601
    }
  )
end

puts "  ✓ #{Appointment.count} agendamentos gerados com sincronização Google Calendar!"
puts "\n================================================================="
puts "  POPULAÇÃO CONCLUÍDA COM SUCESSO! O CRM ESTÁ PRONTO PARA A CLIENTE "
puts "================================================================="
