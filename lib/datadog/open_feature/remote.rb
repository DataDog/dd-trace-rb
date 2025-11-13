# frozen_string_literal: true

require_relative '../core/remote/dispatcher'

module Datadog
  module OpenFeature
    # This module contains the remote configuration functionality for OpenFeature
    module Remote
      ReadError = Class.new(StandardError)

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
            engine = OpenFeature.engine
            break unless engine

            changes.each do |change|
              content = repository[change.path]

              unless content || change.type == :delete
                next telemetry.error("OpenFeature: Remote Configuration change is not present on #{change.type}")
              end

              # NOTE: In the current RC implementation we immediately apply the configuration,
              #       but that might change if we need to apply patches instead.
              case change.type
              when :insert, :update
                begin
                  # @type var content: Core::Remote::Configuration::Content
                  engine.reconfigure!(read_content(content))
                  content.applied
                rescue ReadError => e
                  content.errored("Error reading Remote Configuration content: #{e.message}")
                rescue EvaluationEngine::ReconfigurationError => e
                  content.errored("Error applying OpenFeature configuration: #{e.message}")
                end
              when :delete
                # NOTE: For now, we treat deletion as clearing the configuration
                #       In a multi-config scenario, we might track configs per path
                engine.reconfigure!(nil)
              end
            end
          end

          [receiver]
        end

        private

        def read_content(content)
          data = content.data.read
          content.data.rewind

          raise ReadError, 'EOF reached' if data.nil?

          data
        end
      end
    end
  end
end
