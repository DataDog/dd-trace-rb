# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Agentless
      # Result of one agentless configuration request.
      class Response
        attr_reader :status, :etag, :body, :error, :flag_selection_ignored

        def initialize(status: nil, etag: nil, body: nil, error: nil, flag_selection_ignored: nil)
          @status = status
          @etag = etag
          @body = body
          @error = error
          @flag_selection_ignored = flag_selection_ignored
        end
      end
    end
  end
end
