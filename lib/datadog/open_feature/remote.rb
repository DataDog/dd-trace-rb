# frozen_string_literal: true

require_relative '../core/remote/dispatcher'

module Datadog
  module OpenFeature
    module Remote
      class << self
        FFE_FLAG_CONFIGURATION_RULES = 1 << 46
        FFE_PRODUCTS = ['FFE_FLAGS'].freeze
        FFE_CAPABILITIES = [FFE_FLAG_CONFIGURATION_RULES].freeze

        def capabilities
          FFE_CAPABILITIES
        end

        def products
          FFE_PRODUCTS
        end

        def receivers(telemetry)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(FFE_PRODUCTS)
          receiver = Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, changes|
            changes.each do |change|
              next unless OpenFeature.evaluator

              # TODO: Implement payload reading
              # content = repository[change.path]
              content = StringIO.new(<<~JSON)
              [
                {
                  "flag": "empty_string_flag",
                  "variationType": "STRING",
                  "defaultValue": "default",
                  "targetingKey": "alice",
                  "attributes": {
                    "country": "US"
                  },
                  "result": {
                    "value": ""
                  }
                },
                {
                  "flag": "empty_string_flag",
                  "variationType": "STRING",
                  "defaultValue": "default",
                  "targetingKey": "bob",
                  "attributes": {},
                  "result": {
                    "value": "non_empty"
                  }
                }
              ]
              JSON

              OpenFeature.evaluator.ufc = read_content(content)
            end

            OpenFeature.evaluator.reconfigure!
          end

          [receiver]
        end

        private

        def parse_content(content)
          data = content.data.read
          content.data.rewind

          # FIXME: We should handle it
          raise ReadError, 'EOF reached' if data.nil?

          data
        end
      end
    end
  end
end
