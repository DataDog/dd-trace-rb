# frozen_string_literal: true

require_relative "base"
require_relative "../configuration_value"

module Datadog
  module Core
    module Telemetry
      module Event
        class AppClientConfigurationChange < Base
          attr_reader :changes, :origin

          def type
            "app-client-configuration-change"
          end

          def initialize(changes, origin)
            super()
            @changes = changes
            @origin = origin
          end

          def payload
            {configuration: configuration}
          end

          def configuration
            config = Datadog.configuration

            # @type var res: Array[telemetry_configuration]
            res = @changes.map do |name, value|
              {
                name: name,
                value: Telemetry::ConfigurationValue.convert(value),
                origin: @origin,
                seq_id: Configuration::Option::Precedence::REMOTE_CONFIGURATION.numeric.next,
              }
            end

            # DEV: This seems unnecessary (we send the state of sca_enabled for each remote config change)
            unless config.dig("appsec", "sca_enabled").nil?
              res << {
                name: "appsec.sca_enabled",
                value: config.appsec.sca_enabled,
                origin: "code",
                seq_id: Configuration::Option::Precedence::PROGRAMMATIC.numeric.next,
              }
            end

            res
          end

          def ==(other)
            other.is_a?(AppClientConfigurationChange) && other.changes == @changes && other.origin == @origin
          end

          alias_method :eql?, :==

          def hash
            [self.class, @changes, @origin].hash
          end
        end
      end
    end
  end
end
