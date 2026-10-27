# frozen_string_literal: true

require_relative "../../core/transport/response"

module Datadog
  module OpenFeature
    module Transport
      # Retain status and discovery data, never server error bodies or exception messages.
      class Response
        include Core::Transport::Response

        attr_reader :code, :info

        def initialize(code: nil, info: nil, pre_send: false)
          @code = code
          @info = info
          @pre_send = pre_send
        end

        def ok?
          !!code&.between?(200, 299)
        end

        def internal_error?
          code.nil?
        end

        def pre_send?
          @pre_send
        end
      end
    end
  end
end
