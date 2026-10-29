# frozen_string_literal: true

# == Schema Information
#
# Table name: appointments
#
#  id                          :uuid             not null, primary key
#  category                    :string(100)      default("Geral"), not null
#  custom_attributes           :jsonb            not null
#  description                 :text
#  duration_minutes            :integer          default(60), not null
#  end_time                    :datetime         not null
#  google_calendar_event_id    :string(255)
#  google_calendar_sync_status :string(50)       default("pending")
#  google_meet_link            :string(500)
#  location                    :string(255)
#  price                       :decimal(10, 2)   default(0.0), not null
#  start_time                  :datetime         not null
#  status                      :string(50)       default("scheduled"), not null
#  title                       :string(255)      not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  contact_id                  :uuid
#  conversation_id             :uuid
#  pipeline_item_id            :uuid
#  user_id                     :uuid             not null
#
class Appointment < ApplicationRecord
  STATUSES = %w[scheduled confirmed attended no_show cancelled rescheduled].freeze

  CATEGORIES = [
    { name: 'Avaliação Facial', color: '#967AB4', duration: 45, price: 100.0, description: 'Diagnóstico e plano de tratamento personalizado' },
    { name: 'Harmonização Facial', color: '#C084FC', duration: 90, price: 1800.0, description: 'Preenchimento e alinhamento facial completo' },
    { name: 'Limpeza de Pele Profunda', color: '#3B82F6', duration: 60, price: 220.0, description: 'Higienização, extração e hidratação profunda' },
    { name: 'Toxina Botulínica (Botox)', color: '#EC4899', duration: 45, price: 1200.0, description: 'Aplicação preventiva e corretiva de rugas e linhas' },
    { name: 'Bioestimulador de Colágeno', color: '#F59E0B', duration: 60, price: 1500.0, description: 'Estímulo de firmeza tecidual e rejuvenescimento' },
    { name: 'Laser & Luz Pulsada', color: '#10B981', duration: 45, price: 350.0, description: 'Tratamento de manchas, poros e rejuvenescimento' },
    { name: 'Retorno / Acompanhamento', color: '#6B7280', duration: 30, price: 0.0, description: 'Revisão pós-procedimento e evolução' }
  ].freeze

  belongs_to :user
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :pipeline_item, optional: true

  validates :title, presence: true
  validates :start_time, presence: true
  validates :user_id, presence: true
  validates :category, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :end_time_after_start_time

  before_validation :set_default_end_time, on: [:create, :update]

  scope :for_user, ->(uid) { where(user_id: uid) if uid.present? }
  scope :for_contact, ->(cid) { where(contact_id: cid) if cid.present? }
  scope :for_category, ->(cat) { where(category: cat) if cat.present? }
  scope :for_status, ->(st) { where(status: st) if st.present? }
  scope :in_range, ->(start_d, end_d) {
    if start_d.present? && end_d.present?
      where('start_time >= ? AND start_time <= ?', start_d, end_d)
    elsif start_d.present?
      where('start_time >= ?', start_d)
    elsif end_d.present?
      where('start_time <= ?', end_d)
    end
  }
  scope :upcoming, -> { where('start_time >= ?', Time.current).order(start_time: :asc) }
  scope :ordered, -> { order(start_time: :asc) }

  # Determina se o agendamento deve sincronizar com o Google Calendar.
  # Agendamentos originados de integrações externas (com custom_attributes['source'])
  # não devem sincronizar com o Google Calendar para evitar poluição da agenda.
  def sync_google_calendar?
    custom_attributes['source'].blank?
  end

  # Gera URL para o usuário/cliente adicionar ao Google Calendar em 1 clique
  def google_calendar_url
    start_utc = start_time.utc.strftime('%Y%m%dT%H%M%SZ')
    end_utc = end_time.utc.strftime('%Y%m%dT%H%M%SZ')
    details = [
      description,
      contact.present? ? "Cliente: #{contact.name} (#{contact.phone_number})" : nil,
      "Categoria: #{category}",
      "Profissional: #{user&.name}",
      location.present? ? "Local: #{location}" : nil
    ].compact.join("\n")

    query = {
      action: 'TEMPLATE',
      text: title,
      dates: "#{start_utc}/#{end_utc}",
      details: details,
      location: location || 'Lumom Beauty'
    }

    "https://calendar.google.com/calendar/render?#{query.to_query}"
  end

  private

  def set_default_end_time
    if start_time.present? && (end_time.blank? || end_time <= start_time)
      mins = duration_minutes.to_i.positive? ? duration_minutes.to_i : 60
      self.end_time = start_time + mins.minutes
    end
  end

  def end_time_after_start_time
    return unless start_time.present? && end_time.present?

    if end_time <= start_time
      errors.add(:end_time, 'deve ser posterior à data e hora de início')
    end
  end
end
