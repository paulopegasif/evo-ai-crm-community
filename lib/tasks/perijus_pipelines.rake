# frozen_string_literal: true

namespace :crm do
  desc 'Configura os Pipelines padrão para o PeriJus SaaS (Vendas e Suporte)'
  task setup_perijus_pipelines: :environment do
    admin_user = User.joins(:roles).where(roles: { key: Role::ADMIN_ROLE_KEYS }).order(:created_at).first ||
                 User.order(:created_at).first

    unless admin_user
      puts '❌ Nenhum usuário encontrado no banco de dados para vincular os pipelines.'
      exit 1
    end

    puts "🚀 Configurando pipelines para o PeriJus com o usuário #{admin_user.email}..."

    # -------------------------------------------------------------------------
    # 1. Pipeline Comercial & Vendas SaaS
    # -------------------------------------------------------------------------
    sales_pipeline = Pipeline.find_or_initialize_by(name: 'PeriJus - Vendas & Comercial (SaaS)')
    sales_pipeline.assign_attributes(
      description: 'Pipeline comercial para vendas do SaaS PeriJus (Tráfego Pago, Outbound B2B e Resend)',
      pipeline_type: 'sales',
      visibility: :public,
      is_default: true,
      is_active: true,
      created_by: admin_user,
      custom_fields: {
        'attributes' => %w[tipo_perfil volume_laudos_mes plano_interesse origem_canal motivo_perda],
        'attribute_definitions' => {
          'tipo_perfil' => {
            'attribute_display_name' => 'Perfil do Profissional',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Perito Judicial',
              'Assistente Técnico',
              'Advogado / Escritório',
              'Estudante / Iniciante em Grafotécnica'
            ]
          },
          'volume_laudos_mes' => {
            'attribute_display_name' => 'Volume de Laudos / Mês',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Ainda não atua (0)',
              '1 a 5 laudos/mês',
              '6 a 15 laudos/mês',
              'Mais de 15 laudos/mês'
            ]
          },
          'plano_interesse' => {
            'attribute_display_name' => 'Plano de Interesse',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Plano Mensal',
              'Plano Semestral',
              'Plano Anual',
              'Plano Escritório (Multi-usuário)'
            ]
          },
          'origem_canal' => {
            'attribute_display_name' => 'Canal de Aquisição',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Meta Ads (Instagram / Facebook)',
              'Google Ads (Pesquisa)',
              'Prospecção B2B (Gmail)',
              'Email Marketing (Resend)',
              'Landing Page Orgânica / Direto',
              'Indicação de Perito'
            ]
          },
          'motivo_perda' => {
            'attribute_display_name' => 'Motivo de Perda',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Preço / Orçamento',
              'Sem demandas no momento',
              'Prefere fazer manual no Word',
              'Utiliza outra ferramenta',
              'Não respondeu às tentativas',
              'Outro'
            ]
          }
        }
      }
    )
    sales_pipeline.save!

    sales_stages_data = [
      { name: 'Novo Lead', color: '#3B82F6', position: 1, stage_type: :active, description: 'Leads capturados via tráfego pago, outbound B2B ou landing page' },
      { name: 'Qualificação & Perfil', color: '#F59E0B', position: 2, stage_type: :active, description: 'Identificação de perfil (Perito, Assistente ou Advogado) e volume de demandas' },
      { name: 'Demonstração / Trial', color: '#8B5CF6', position: 3, stage_type: :active, description: 'Degustação do PeriJus, envio de tour ou teste prático de geração de laudos' },
      { name: 'Proposta & Negociação', color: '#EC4899', position: 4, stage_type: :active, description: 'Apresentação dos planos (Mensal/Anual), superação de objeções e checkout' },
      { name: 'Fechado Ganho (Assinante)', color: '#10B981', position: 5, stage_type: :completed, description: 'Assinatura confirmada e acesso liberado à plataforma PeriJus' },
      { name: 'Perdido / Sem Perfil', color: '#EF4444', position: 6, stage_type: :cancelled, description: 'Lead sem fit, sem demanda ou descarte com motivo registrado' },
      { name: 'Nutrição (Resend)', color: '#64748B', position: 7, stage_type: :active, description: 'Sequência de e-mails para aquecimento e conversão futura' }
    ]

    sales_stages_data.each do |s|
      stage = sales_pipeline.pipeline_stages.find_or_initialize_by(position: s[:position])
      stage.assign_attributes(
        name: s[:name],
        color: s[:color],
        stage_type: s[:stage_type],
        automation_rules: { description: s[:description] }
      )
      stage.save!
    end

    puts "✅ Pipeline Comercial criado/atualizado: #{sales_pipeline.name} com #{sales_stages_data.size} etapas!"

    # -------------------------------------------------------------------------
    # 2. Pipeline de Suporte & Sucesso do Cliente
    # -------------------------------------------------------------------------
    support_pipeline = Pipeline.find_or_initialize_by(name: 'PeriJus - Suporte & Sucesso do Cliente')
    support_pipeline.assign_attributes(
      description: 'Pipeline de atendimento, suporte técnico e retenção dos peritos e assinantes do PeriJus',
      pipeline_type: 'support',
      visibility: :public,
      is_default: false,
      is_active: true,
      created_by: admin_user,
      custom_fields: {
        'attributes' => %w[tipo_chamado prioridade numero_processo status_resolucao],
        'attribute_definitions' => {
          'tipo_chamado' => {
            'attribute_display_name' => 'Tipo de Chamado',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Dúvida de Grafotécnica / Laudo Cypriano',
              'Problema Técnico / Geração de PDF / Imagens',
              'Dúvida de Assinatura / Pagamento / Cartão',
              'Dificuldade de Acesso / Login',
              'Sugestão de Nova Funcionalidade'
            ]
          },
          'prioridade' => {
            'attribute_display_name' => 'Prioridade',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Baixa',
              'Média',
              'Alta',
              'Urgente (Prazo Judicial)'
            ]
          },
          'numero_processo' => {
            'attribute_display_name' => 'Número do Processo Judicial',
            'attribute_display_type' => 'text'
          },
          'status_resolucao' => {
            'attribute_display_name' => 'Desfecho da Resolução',
            'attribute_display_type' => 'list',
            'attribute_values' => [
              'Orientação Fornecida',
              'Bug Corrigido',
              'Assinatura Ajustada',
              'Retido com Sucesso',
              'Cancelamento Efetivado'
            ]
          }
        }
      }
    )
    support_pipeline.save!

    support_stages_data = [
      { name: 'Novo Chamado', color: '#3B82F6', position: 1, stage_type: :active, description: 'Tickets recém-chegados por WhatsApp, Gmail ou Chat da plataforma' },
      { name: 'Triagem & Diagnóstico', color: '#F59E0B', position: 2, stage_type: :active, description: 'Classificação: Laudos/Grafotécnica, Suporte Técnico ou Faturamento' },
      { name: 'Em Atendimento', color: '#8B5CF6', position: 3, stage_type: :active, description: 'Equipe ou agente IA atuando diretamente na resolução' },
      { name: 'Aguardando Cliente', color: '#6366F1', position: 4, stage_type: :active, description: 'Orientação enviada, aguardando validação ou retorno do perito' },
      { name: 'Resolvido', color: '#10B981', position: 5, stage_type: :completed, description: 'Problema sanado e confirmado pelo perito judicial' },
      { name: 'Risco de Churn', color: '#EF4444', position: 6, stage_type: :active, description: 'Cliente insatisfeito ou pedindo cancelamento com ação preventiva de retenção' }
    ]

    support_stages_data.each do |s|
      stage = support_pipeline.pipeline_stages.find_or_initialize_by(position: s[:position])
      stage.assign_attributes(
        name: s[:name],
        color: s[:color],
        stage_type: s[:stage_type],
        automation_rules: { description: s[:description] }
      )
      stage.save!
    end

    puts "✅ Pipeline de Suporte criado/atualizado: #{support_pipeline.name} com #{support_stages_data.size} etapas!"
    puts '🎉 Configuração dos Pipelines PeriJus SaaS concluída com sucesso!'
  end
end
