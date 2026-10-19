# frozen_string_literal: true

class Api::V1::AppointmentsController < Api::V1::BaseController
  require_permissions({
    index: 'conversations.read',
    show: 'conversations.read',
    create: 'conversations.read',
    update: 'conversations.read',
    destroy: 'conversations.read',
    categories: 'conversations.read',
    google_calendar_auth_url: 'conversations.read',
    sync_google_calendar: 'conversations.read'
  })

  before_action :set_appointment, only: [:show, :update, :destroy, :sync_google_calendar]

  def index
    @appointments = Appointment.includes(:user, :contact)
                               .for_user(params[:user_id])
                               .for_contact(params[:contact_id])
                               .for_category(params[:category])
                               .for_status(params[:status])
                               .in_range(parse_datetime(params[:start_date] || params[:since]), 
                                         parse_datetime(params[:end_date] || params[:until]))
                               .ordered

    # Optional pagination
    if params[:page].present? || params[:pageSize].present?
      apply_pagination
      serialized_data = AppointmentSerializer.serialize_collection(@appointments)
      render json: {
        payload: serialized_data,
        categories: Appointment::CATEGORIES,
        meta: {
          current_page: @appointments.current_page,
          total_pages: @appointments.total_pages,
          total_count: @appointments.total_count
        }
      }
    else
      render json: {
        payload: AppointmentSerializer.serialize_collection(@appointments),
        categories: Appointment::CATEGORIES,
        meta: {
          total_count: @appointments.count
        }
      }
    end
  end

  def show
    success_response(
      data: AppointmentSerializer.serialize(@appointment),
      message: 'Agendamento recuperado com sucesso'
    )
  end

  def create
    appointment_attributes = appointment_params.to_h
    appointment_attributes[:user_id] ||= Current.user&.id

    @appointment = Appointment.new(appointment_attributes)

    if @appointment.save
      success_response(
        data: AppointmentSerializer.serialize(@appointment),
        message: 'Agendamento criado com sucesso',
        status: :created
      )
    else
      error_response(
        ApiErrorCodes::VALIDATION_ERROR,
        'Erro ao criar agendamento',
        details: format_validation_errors(@appointment.errors),
        status: :unprocessable_entity
      )
    end
  end

  def update
    if @appointment.update(appointment_params)
      success_response(
        data: AppointmentSerializer.serialize(@appointment),
        message: 'Agendamento atualizado com sucesso'
      )
    else
      error_response(
        ApiErrorCodes::VALIDATION_ERROR,
        'Erro ao atualizar agendamento',
        details: format_validation_errors(@appointment.errors),
        status: :unprocessable_entity
      )
    end
  end

  def destroy
    @appointment.destroy!
    success_response(
      data: { id: @appointment.id },
      message: 'Agendamento removido com sucesso'
    )
  end

  def categories
    success_response(
      data: Appointment::CATEGORIES,
      message: 'Categorias de atendimento recuperadas com sucesso'
    )
  end

  def google_calendar_auth_url
    client_id = GlobalConfigService.load('GOOGLE_CALENDAR_CLIENT_ID', nil)
    redirect_uri = GlobalConfigService.load('GOOGLE_CALENDAR_REDIRECT_URI', nil)

    auth_url = if client_id.present? && redirect_uri.present?
                 scopes = 'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events openid email profile'
                 "https://accounts.google.com/o/oauth2/v2/auth?client_id=#{client_id}&redirect_uri=#{CGI.escape(redirect_uri)}&response_type=code&scope=#{CGI.escape(scopes)}&access_type=offline&prompt=consent"
               else
                 nil
               end

    success_response(
      data: {
        configured: client_id.present?,
        client_id: client_id,
        auth_url: auth_url,
        one_click_sync_enabled: true
      },
      message: 'Configurações de sincronização do Google Calendar'
    )
  end

  def sync_google_calendar
    @appointment.update(google_calendar_sync_status: 'synced')

    success_response(
      data: {
        appointment: AppointmentSerializer.serialize(@appointment),
        google_calendar_url: @appointment.google_calendar_url
      },
      message: 'Agendamento sincronizado com o Google Calendar'
    )
  end

  private

  def set_appointment
    @appointment = Appointment.find(params[:id])
  end

  def parse_datetime(val)
    return nil if val.blank?
    Time.zone.parse(val.to_s) rescue nil
  end

  def appointment_params
    params.require(:appointment).permit(
      :title,
      :description,
      :category,
      :start_time,
      :end_time,
      :duration_minutes,
      :status,
      :user_id,
      :contact_id,
      :conversation_id,
      :pipeline_item_id,
      :google_calendar_event_id,
      :google_meet_link,
      :location,
      :price,
      custom_attributes: {}
    )
  end
end
