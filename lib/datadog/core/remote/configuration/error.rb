# frozen_string_literal: true

require_relative "../../utils/truncation"

module Datadog
  module Core
    module Remote
      class Configuration
        # Error raised when a remote configuration payload value has an
        # unexpected type.
        class Error < TypeError
          # Builds the error for a remote configuration payload value that has
          # an unexpected type. The offending value is reported truncated to
          # its first 100 and last 50 characters.
          def self.invalid_data_type(value, field:, expected_type:)
            new(
              "Invalid type for #{field}: expected #{expected_type}: " \
                "#{Core::Utils::Truncation.truncate_in_middle(value.inspect, 100, 50)}"
            )
          end
        end
      end
    end
  end
end
