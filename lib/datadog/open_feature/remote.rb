# frozen_string_literal: true

require_relative '../core/remote/dispatcher'

module Datadog
  module OpenFeature
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
                next telemetry.error("OpenFeature: RemoteConfig change is not present on #{change.type}")
              end

              # NOTE: We don't validate config and immediately mark content as
              #       applied, even tho it might be a failure.
              #
              #       The re-configuration process is fail-safe by itself and
              #       will be changed once RC updated to deliver patches.
              case change.type
              when :insert, :update
                # @type var content: Core::Remote::Configuration::Content
                engine.configuration = read_content(content)
                content.applied
              when :delete
                # NOTE: For now, we treat deletion as clearing the configuration
                #       In a multi-config scenario, we might track configs per path
                engine.configuration = nil
              end
            end

            engine.reconfigure!
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
