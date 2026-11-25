# frozen_string_literal: true

# O que está esperando ação agora: conversas sem resposta, follow-ups vencidos e propostas paradas.
module BusinessAssistant
  module Queries
    class Pending
      LIST_LIMIT = 10

      def call
        counts = DailyPanel::BuildService.new(user: nil, admin: true, today: Sales::TimeZone.today).call[:todo]
        counts.merge(
          awaiting_reply_list: awaiting_reply_list,
          overdue_follow_ups_list: overdue_follow_ups_list
        )
      end

      private

      def awaiting_reply_list
        DailySummary::Exclusion.conversations(Conversation.open.unattended)
                               .where.not(contact_id: DailySummary::Exclusion.internal_contact_ids)
                               .includes(:contact, :inbox)
                               .order(:last_activity_at).limit(LIST_LIMIT)
                               .map do |conversation|
          { conversation_id: conversation.id, contact: conversation.contact&.name, inbox: conversation.inbox&.name,
            waiting_since: conversation.last_activity_at&.iso8601 }
        end
      end

      def overdue_follow_ups_list
        PipelineTask.where(task_type: PipelineTask.task_types[:follow_up])
                    .where(status: [PipelineTask.statuses[:pending], PipelineTask.statuses[:overdue]])
                    .where('pipeline_tasks.due_date < ?', Time.current)
                    .order(:due_date).limit(LIST_LIMIT)
                    .map { |task| { id: task.id, title: task.title, due_date: task.due_date&.iso8601 } }
      end
    end
  end
end
