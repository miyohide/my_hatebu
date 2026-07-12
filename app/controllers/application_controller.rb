# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ApiKeyAuthenticatable

  rescue_from StandardError, with: :render_internal_server_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  def render_not_found(exception)
    render json: { error: { code: 'not_found', message: exception.message } }, status: :not_found
  end

  def render_bad_request(exception)
    render json: { error: { code: 'bad_request', message: exception.message } }, status: :bad_request
  end

  def render_internal_server_error(exception)
    Rails.logger.error("Unhandled exception: #{exception.class} - #{exception.message}")
    Rails.logger.error(exception.backtrace&.first(20)&.join("\n"))

    render json: { error: { code: 'internal_server_error', message: '内部サーバーエラーが発生しました' } }, status: :internal_server_error
  end
end
