# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Wrapper class for evaluation API response
      class Result
        ALLOW_ACTION = "ALLOW"
        DENY_ACTION = "DENY"
        ABORT_ACTION = "ABORT"

        attr_reader :action, :reason, :tags, :sds_findings, :tag_probabilities

        def initialize(raw_response)
          attributes = raw_response.fetch("data").fetch("attributes")

          @action = attributes.fetch("action")
          @reason = attributes.fetch("reason")
          @tags = attributes.fetch("tags")
          @tag_probabilities = attributes.fetch("tag_probs")
          @is_blocking_enabled = attributes.fetch("is_blocking_enabled")
          @sds_findings = attributes.fetch("sds_findings", [])
        rescue KeyError => e
          raise AIGuardClientError, "Missing key: \"#{e.key}\""
        end

        def allow?
          action == ALLOW_ACTION
        end

        def deny?
          action == DENY_ACTION
        end

        def abort?
          action == ABORT_ACTION
        end

        def blocking_enabled?
          !!@is_blocking_enabled
        end
      end
    end
  end
end
