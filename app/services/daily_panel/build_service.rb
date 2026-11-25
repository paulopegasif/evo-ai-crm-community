# frozen_string_literal: true

# Monta o Painel do Dia numa única resposta. Administrador vê a empresa toda; demais
# usuários veem só as próprias vendas, conversas atribuídas, tarefas e cards.
module DailyPanel
  class BuildService
    STALLED_AFTER = 3.days

    def initialize(user:, admin:, today: Sales::TimeZone.today)
      @user = user
      @admin = admin
      @today = today
    end

    def call
      today_sales = day_totals(@today)
      todo = build_todo
      {
        generated_at: Time.current.iso8601,
        timezone: Sales::TimeZone.current.tzinfo.name,
        user: { first_name: first_name, is_admin: @admin },
        quote: QuotePicker.pick(QuotePicker.category_for(@user), date: @today),
        sales: {
          today: today_sales,
          yesterday: day_totals(@today - 1),
          same_weekday_last_week: day_totals(@today - 7)
        },
        month: build_month,
        todo: todo,
        no_sales_hint: today_sales[:count].zero? ? todo.slice(:stalled_items, :awaiting_reply) : nil
      }
    end

    private

    def first_name
      @user&.name.to_s.split.first || ''
    end

    def sales_scope
      scope = Sale.active
      @admin ? scope : scope.for_seller(@user)
    end

    def day_totals(date)
      scope = sales_scope.on_day(date)
      { count: scope.count, amount: scope.sum(:amount).to_f }
    end

    def build_month
      month = @today.beginning_of_month
      goal = SalesGoal.for_month(month).find_by(user_id: @admin ? nil : @user&.id)
      progress = SalesGoals::ProgressService.new(month: month, goal: goal, seller: @admin ? nil : @user, today: @today).call
      progress.merge(month: month.strftime('%Y-%m'), scope: @admin ? 'all' : 'mine')
    end

    def build_todo
      {
        awaiting_reply: awaiting_reply.count,
        overdue_follow_ups: overdue_follow_ups.count,
        stalled_items: stalled_items.count,
        sales_missing_amount: sales_scope.where(missing_amount: true).count
      }
    end

    def awaiting_reply
      scope = DailySummary::Exclusion.conversations(Conversation.open.unattended)
      scope = scope.where.not(contact_id: DailySummary::Exclusion.internal_contact_ids)
      @admin ? scope : scope.where(assignee_id: @user&.id)
    end

    def overdue_follow_ups
      scope = PipelineTask.where(task_type: PipelineTask.task_types[:follow_up])
                          .where(status: [PipelineTask.statuses[:pending], PipelineTask.statuses[:overdue]])
                          .where('pipeline_tasks.due_date < ?', Time.current)
      @admin ? scope : scope.where(assigned_to_id: @user&.id)
    end

    def stalled_items
      last_move = 'COALESCE((SELECT MAX(sm.created_at) FROM stage_movements sm WHERE sm.pipeline_item_id = pipeline_items.id), ' \
                  'pipeline_items.entered_at, pipeline_items.created_at)'
      scope = PipelineItem.joins(:pipeline, :pipeline_stage)
                          .where.not(pipelines: { pipeline_type: 'support' })
                          .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:active] })
                          .where("#{last_move} < ?", STALLED_AFTER.ago)
      return scope if @admin

      scope.left_joins(:conversation).where(conversations: { assignee_id: @user&.id })
    end
  end
end
