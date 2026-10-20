# frozen_string_literal: true

require_relative "../utils/truncation"
require_relative "configuration/path"
require_relative "configuration/content"
require_relative "configuration/target"
require_relative "configuration/repository"

module Datadog
  module Core
    module Remote
      class Configuration
        class << self
          # Builds the message for an exception raised because a remote config
          # payload value has an unexpected type. The offending value is
          # reported truncated to its first 100 and last 50 characters.
          def invalid_type_message(field, value, expected_type)
            "Invalid type for #{field}: expected #{expected_type}: " \
              "#{Core::Utils::Truncation.truncate_in_middle(value.inspect, 100, 50)}"
          end
        end
      end
    end
  end
end
