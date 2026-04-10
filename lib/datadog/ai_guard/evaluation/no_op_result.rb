# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Class for emulating AI Guard evaluation result when AI Guard is disabled.
      class NoOpResult
        attr_reader :action, :reason, :tags, :sds_findings

        def initialize
          @action = Result::ALLOW_ACTION
          @reason = "AI Guard is disabled"
          @tags = []
          @sds_findings = []
        end

        def allow?
          true
        end

        def deny?
          false
        end

        def abort?
          false
        end

        def blocking_enabled?
          false
        end
      end
    end
  end
end
