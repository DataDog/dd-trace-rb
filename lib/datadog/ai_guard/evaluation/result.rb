# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      class Result
        ALLOW_ACTION = "ALLOW"
        DENY_ACTION = "DENY"
        ABORT_ACTION = "ABORT"

        attr_reader :messages, :action, :reason, :tags, :sds_findings,
                    :tag_probabilities

        def initialize(messages, action:, reason:, tags:, sds_findings:, tag_probabilities:)
          @messages = messages
          @action = action
          @reason = reason
          @tags = tags
          @sds_findings = sds_findings
          @tag_probabilities = tag_probabilities
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
      end
    end
  end
end
