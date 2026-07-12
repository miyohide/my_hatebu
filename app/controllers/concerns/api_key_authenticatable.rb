# frozen_string_literal: true

module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
  end

  private

  def authenticate_api_key!
    api_key = request.headers['X-API-Key']
    expected_key = ENV.fetch('API_KEY', nil)

    unless api_key.present? && expected_key.present? &&
           ActiveSupport::SecurityUtils.secure_compare(api_key, expected_key)
      render json: { error: { code: 'unauthorized', message: '認証に失敗しました' } }, status: :unauthorized
    end
  end
end
