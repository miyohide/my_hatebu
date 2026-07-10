# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :authenticate_api_key!

  def show
    render json: { status: "ok" }
  end
end
