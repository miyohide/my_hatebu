# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
ENV['API_KEY'] ||= 'test_api_key_12345'

require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'mocha/minitest'

# Explicitly disable external network connections in tests
WebMock.disable_net_connect!

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Returns authentication headers with a valid API key
    def api_key_headers
      { 'X-API-Key' => 'test_api_key_12345' }
    end

    # Returns authentication headers merged with JSON content type
    def authenticated_json_headers
      api_key_headers.merge('Content-Type' => 'application/json')
    end
  end
end
