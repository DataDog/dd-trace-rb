# frozen_string_literal: true

require "forwardable"

module Datadog
  module AIGuard
    module Evaluation
      class Result
        extend Forwardable

        def_delegators :@response, :action, :reason, :tags, :tag_probabilities,
                                   :sds_findings, :redaction_replacements,
                                   :allow?, :deny?, :abort?, :blocking_enabled?

        attr_reader :messages

        def initialize(response, messages:)
          @response = response
          @messages = messages
        end
      end
    end
  end
end
