# frozen_string_literal: true

# Pipeline comercial do serviço "CRM Elph" (implantação + mensalidade), separado dos
# pipelines do PeriJus. Os leads da campanha chegam pelo MESMO WhatsApp do PeriJus; quem
# separa é a automação criada aqui: mensagem recebida contendo a frase da mensagem
# pré-preenchida do anúncio (ELPH_CRM_KEYWORD) → move a conversa para este pipeline e
# etiqueta com `crm-elph`.
#
#   bundle exec rake crm:setup_elph_crm_pipeline
#   ELPH_CRM_KEYWORD="crm da elph" bundle exec rake crm:setup_elph_crm_pipeline
#
# Idempotente: reexecutar só atualiza nomes, cores e campos.
namespace :crm do
  desc 'Configura o pipeline "CRM Elph - Vendas" e a automação que roteia os leads da campanha'
  task setup_elph_crm_pipeline: :environment do
    admin_user = User.joins(:roles).where(roles: { key: Role::ADMIN_ROLE_KEYS }).order(:created_at).first ||
                 User.order(:created_at).first
    abort '❌ Nenhum usuário encontrado para vincular o pipeline.' unless admin_user

    keyword = ENV.fetch('ELPH_CRM_KEYWORD', 'crm da elph').downcase.strip
    label_name = 'crm-elph'

    pipeline = Pipeline.find_or_initialize_by(name: 'CRM Elph - Vendas')
    pipeline.assign_attributes(
      description: 'Vendas do CRM Elph (implantação em 7 dias + mensalidade): clínicas, escritórios, infoprodutores e PMEs',
      pipeline_type: 'sales',
      visibility: :public,
      is_active: true,
      created_by: admin_user,
      custom_fields: {
        'attributes' => %w[nicho tamanho_equipe ferramenta_atual interesse origem_canal motivo_perda],
        'attribute_definitions' => {
          'nicho' => {
            'attribute_display_name' => 'Nicho',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Clínica / Consultório',
              'Escritório de Advocacia',
              'Escritório de Contabilidade',
              'Infoprodutor / Cursos',
              'Outro'
            ]
          },
          'tamanho_equipe' => {
            'attribute_display_name' => 'Pessoas no Atendimento/Comercial',
            'attribute_display_type' => 'list',
            'attribute_values' => ['Só eu', '2 a 5', '6 a 15', 'Mais de 15']
          },
          'ferramenta_atual' => {
            'attribute_display_name' => 'Ferramenta Atual',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Nenhuma / WhatsApp no celular',
              'Planilha',
              'Bitrix24',
              'RD Station CRM',
              'Kommo',
              'HubSpot',
              'Outra'
            ]
          },
          'interesse' => {
            'attribute_display_name' => 'Interesse',
            'attribute_display_type' => 'list',
            'attribute_values' => ['CRM', 'CRM + Agentes de IA', 'Só Agentes de IA']
          },
          'origem_canal' => {
            'attribute_display_name' => 'Canal de Aquisição',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Meta Ads (Instagram / Facebook)',
              'Google Ads',
              'Indicação',
              'Orgânico / Direto',
              'Prospecção Ativa'
            ]
          },
          'motivo_perda' => {
            'attribute_display_name' => 'Motivo de Perda',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Preço / Orçamento',
              'Sem momento / Vai deixar para depois',
              'Fechou com outra ferramenta',
              'Sem fit (operação pequena demais)',
              'Não respondeu às tentativas',
              'Outro'
            ]
          }
        }
      }
    )
    pipeline.save!

    stages = [
      { name: 'Novo Lead', color: '#3B82F6', stage_type: :active, description: 'Chegou pelo anúncio (mensagem "CRM da Elph") ou outro canal' },
      { name: 'Qualificação', color: '#F59E0B', stage_type: :active, description: 'Nicho, tamanho da equipe, ferramenta atual e interesse em agentes de IA' },
      { name: 'Diagnóstico Agendado', color: '#8B5CF6', stage_type: :active, description: 'Reunião de diagnóstico / demonstração marcada' },
      { name: 'Proposta Enviada', color: '#EC4899', stage_type: :active, description: 'Proposta de implantação + mensalidade enviada' },
      { name: 'Negociação', color: '#6366F1', stage_type: :active, description: 'Objeções, ajustes de escopo e fechamento' },
      { name: 'Fechado Ganho', color: '#10B981', stage_type: :completed, description: 'Contrato fechado: iniciar implantação (7 dias)' },
      { name: 'Perdido', color: '#EF4444', stage_type: :cancelled, description: 'Sem fit ou sem resposta, com motivo registrado' }
    ]

    stages.each.with_index(1) do |s, position|
      stage = pipeline.pipeline_stages.find_or_initialize_by(position: position)
      stage.assign_attributes(name: s[:name], color: s[:color], stage_type: s[:stage_type],
                              automation_rules: { description: s[:description] })
      stage.save!
    end
    puts "✅ Pipeline: #{pipeline.name} (#{pipeline.id}) com #{stages.size} etapas"

    Label.find_or_create_by!(title: label_name) do |label|
      label.description = 'Lead da campanha do CRM Elph'
      label.color = '#C8F135'
      label.show_on_sidebar = true
    end

    rule = AutomationRule.find_or_initialize_by(name: 'CRM Elph: mensagem do anúncio → pipeline CRM Elph')
    rule.assign_attributes(
      description: "Mensagem recebida contendo \"#{keyword}\" move a conversa para o pipeline CRM Elph - Vendas",
      event_name: 'message_created',
      active: true,
      conditions: [
        { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['incoming'], 'query_operator' => 'and' },
        { 'attribute_key' => 'content', 'filter_operator' => 'contains', 'values' => [keyword], 'query_operator' => nil }
      ],
      actions: [
        { 'action_name' => 'assign_to_pipeline', 'action_params' => [pipeline.id] },
        { 'action_name' => 'add_label', 'action_params' => [label_name] }
      ]
    )
    rule.save!
    puts "✅ Automação: #{rule.name} (palavra-chave: \"#{keyword}\")"
  end
end
