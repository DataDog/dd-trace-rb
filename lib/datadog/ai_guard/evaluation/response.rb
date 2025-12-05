# frozen_string_literal: true

module Datadog
  module AIGuard
    class Evaluation
      # Wrapper class for evaluation API response
      class Response
        ALLOW_ACTION = 'ALLOW'
        DENY_ACTION = 'DENY'
        ABORT_ACTION = 'ABORT'

        attr_reader :action, :reason, :tags

        def initialize(raw_response)
          attributes = raw_response.fetch('data').fetch('attributes')

          @action = attributes.fetch('action')
          @reason = attributes.fetch('reason')
          @tags = attributes.fetch('tags')

        end
        # TODO: handle missing key errors

        def allow?
          action == ALLOW_ACTION
        end

        def deny?
          action == DENY_ACTION
        end

        def abort?
          action == ABORT_ACTION
        end
      end
    end
  end
end
