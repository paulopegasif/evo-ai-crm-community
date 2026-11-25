# frozen_string_literal: true

class Api::V1::SalesGoalsController < Api::V1::BaseController
  include PainelDoDiaAccess

  before_action :require_admin!

  def index
    month = parse_month(params[:month]) || Sales::TimeZone.today.beginning_of_month
    goals = SalesGoal.for_month(month).index_by(&:user_id)

    sellers = User.order(:name).map do |user|
      { user: { id: user.id, name: user.name } }
        .merge(SalesGoals::ProgressService.new(month: month, goal: goals[user.id], seller: user).call)
    end

    success_response(data: {
                       month: month.strftime('%Y-%m'),
                       general: SalesGoals::ProgressService.new(month: month, goal: goals[nil]).call,
                       sellers: sellers
                     })
  end

  def upsert
    month = parse_month(params[:month])
    return error_response(ApiErrorCodes::VALIDATION_ERROR, 'month inválido (use AAAA-MM)', status: :unprocessable_entity) unless month

    user = params[:user_id].presence && User.find_by(id: params[:user_id])
    return not_found('User not found') if params[:user_id].present? && user.nil?

    goal = SalesGoal.find_or_initialize_by(month: month, user_id: user&.id)
    goal.amount = params[:amount]
    return record_validation_error(goal) unless goal.save

    success_response(data: SalesGoals::ProgressService.new(month: month, goal: goal, seller: user).call,
                     message: 'Goal saved')
  end

  def destroy
    goal = SalesGoal.find_by(id: params[:id])
    return not_found('Goal not found') unless goal

    goal.destroy!
    success_response(data: { id: goal.id }, message: 'Goal removed')
  end

  private

  def parse_month(value)
    return if value.blank?

    Date.strptime(value.to_s[0, 7], '%Y-%m')
  rescue Date::Error
    nil
  end
end
