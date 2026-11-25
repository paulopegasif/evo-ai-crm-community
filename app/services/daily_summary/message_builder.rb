# frozen_string_literal: true

# Texto curto do resumo diário, pensado para leitura no celular (WhatsApp).
module DailySummary
  class MessageBuilder
    WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

    def initialize(date: Sales::TimeZone.today, test: false)
      @date = date
      @test = test
    end

    def call
      panel = DailyPanel::BuildService.new(user: nil, admin: true, today: @date).call
      today = panel[:sales][:today]
      lines = []
      lines << "#{@test ? '[TESTE] ' : ''}*Resumo do dia — #{WEEKDAYS[@date.wday]}, #{@date.strftime('%d/%m')}*"
      lines << ''
      lines << if today[:count].positive?
                 "💰 Vendas: #{today[:count]} (#{money(today[:amount])})"
               else
                 '💰 Nenhuma venda hoje.'
               end
      lines << "🙋 Leads novos: #{new_leads_count}"
      lines << "💬 Aguardando resposta: #{panel[:todo][:awaiting_reply]}"
      lines << "⏰ Follow-ups vencidos: #{panel[:todo][:overdue_follow_ups]}"
      lines.concat(goal_lines(panel[:month]))
      lines.concat(opportunity_lines(panel[:todo])) if today[:count].zero?
      lines.join("\n")
    end

    private

    def goal_lines(month)
      return [] if month[:goal].blank?

      if month[:goal_reached]
        ["🎯 Meta do mês batida! #{money(month[:sold])} de #{money(month[:goal])}"]
      else
        ["🎯 Meta do mês: #{month[:percent].to_s.sub('.', ',')}% · faltam #{money(month[:remaining])} " \
         "(≈ #{money(month[:daily_pace])}/dia)"]
      end
    end

    def opportunity_lines(todo)
      items = []
      items << "#{todo[:stalled_items]} propostas paradas" if todo[:stalled_items].positive?
      items << "#{todo[:awaiting_reply]} leads aguardando resposta" if todo[:awaiting_reply].positive?
      return [] if items.empty?

      ['', "👉 Oportunidades em aberto: #{items.join(', ')}."]
    end

    def new_leads_count
      Contact.where(created_at: Sales::TimeZone.day_range(@date))
             .where.not(id: DailySummary::Exclusion.internal_contact_ids).count
    end

    def money(value)
      ActiveSupport::NumberHelper.number_to_currency(value.to_f, unit: 'R$ ', separator: ',', delimiter: '.', precision: 2)
    end
  end
end
