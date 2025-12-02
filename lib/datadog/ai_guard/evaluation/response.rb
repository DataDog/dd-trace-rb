# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Wrapper class for evaluation API response
      class Response
        ACTIONS = {
          "ALLOW" => :allow,
          "DENY" => :deny,
          "ABORT" => :abort
        }.freeze

        attr_reader :action, :reason, :tags

        def initialize(raw_response)
          attributes = raw_response.fetch('data').fetch('attributes')

          @action = ACTIONS.fetch(attributes.fetch('action'))
          @reason = attributes.fetch('reason')
          @tags = attributes.fetch('tags')

          # TODO: handle missing key errors or unknown actions
        end

        def allow?
          action == :allow
        end

        def deny?
          action == :deny
        end

        def abort?
          action == :abort
        end
      end
    end
  end
end
