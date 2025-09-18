# frozen_string_literal: true

module Datadog
  module AppSec
    module SecurityEngine
      # A namespace for value-objects representing the result of WAF check.
      module Result
        # A generic result without indication of its type.
        class Base
          attr_reader :events, :actions, :attributes, :duration_ns, :duration_ext_ns

          def initialize(events:, actions:, attributes:, duration_ns:, duration_ext_ns:, timeout:, keep:, input_truncated:)
            @events = events
            @actions = actions
            @attributes = attributes

            @keep = keep
            @timeout = timeout
            @duration_ns = duration_ns
            @duration_ext_ns = duration_ext_ns
            @input_truncated = input_truncated
          end

          def timeout?
            !!@timeout
          end

          def keep?
            !!@keep
          end

          def match?
            raise NotImplementedError
          end

          def error?
            raise NotImplementedError
          end

          def input_truncated?
            @input_truncated
          end
        end

        # A result that indicates a security rule match
        class Match < Base
          def match?
            true
          end

          def error?
            false
          end
        end

        # A result that indicates a successful security rules check without a match
        class Ok < Base
          def match?
            false
          end

          def error?
            false
          end
        end

        # A result that indicates an internal security library error
        class Error
          attr_reader :events, :actions, :attributes, :duration_ns, :duration_ext_ns

          def initialize(duration_ext_ns:, input_truncated:)
            @events = []
            @actions = @attributes = {}
            @duration_ns = 0
            @duration_ext_ns = duration_ext_ns
            @input_truncated = input_truncated
          end

          # NOTE: If an error happened we definitely would like to have access to
          #       the span or the trace to be able to detect an issue.
          def keep?
            true
          end

          def timeout?
            false
          end

          def match?
            false
          end

          def error?
            true
          end

          def input_truncated?
            @input_truncated
          end
        end
      end
    end
  end
end
