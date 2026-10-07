# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Agentless
      # Result of one agentless configuration request.
      class Response
        attr_reader :status, :etag, :body, :error

        def initialize(status: nil, etag: nil, body: nil, error: nil)
          @status = status
          @etag = etag
          @body = body
          @error = error
        end
      end
    end
  end
end
