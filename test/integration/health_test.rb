# frozen_string_literal: true

require 'test_helper'

class HealthTest < ActionDispatch::IntegrationTest
  test 'returns 200 with status ok' do
    get '/health'

    assert_response :success
    json = response.parsed_body

    assert_equal 'ok', json['status']
  end

  test 'does not require authentication' do
    get '/health'

    assert_response :success
  end

  test 'returns json content type' do
    get '/health'

    assert_match 'application/json', response.content_type
  end
end
