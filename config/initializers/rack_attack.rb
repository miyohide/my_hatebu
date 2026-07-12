# frozen_string_literal: true

module Rack
  class Attack
    # Throttle API requests by IP address
    # Default: 10 requests per minute (configurable via RATE_LIMIT_PER_MINUTE)
    throttle('api/ip', limit: proc { (ENV['RATE_LIMIT_PER_MINUTE'] || 10).to_i }, period: 1.minute) do |req|
      # Only apply to /api/ paths, exclude /health
      req.ip if req.path.start_with?('/api/')
    end

    # Return 429 with JSON error response when throttled
    self.throttled_responder = lambda do |_req|
      body = { error: { code: 'rate_limit_exceeded', message: 'リクエスト数が制限を超えました。しばらく待ってから再試行してください' } }.to_json
      [429, { 'Content-Type' => 'application/json' }, [body]]
    end
  end
end
