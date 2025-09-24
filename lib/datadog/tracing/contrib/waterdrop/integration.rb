# frozen_string_literal: true

require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Description of WaterDrop integration
        class Integration
          include Contrib::Integration

          # Minimum version of the WaterDrop library that we support
          MINIMUM_VERSION = Gem::Version.new('2.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :waterdrop, auto_patch: true

          def self.gem_name
            'waterdrop'
          end

          def self.version
            Gem.loaded_specs['waterdrop']&.version
          end

          def self.loaded?
            loaded = !defined?(::WaterDrop).nil?
            puts "🔍 [WATERDROP INTEGRATION] loaded? = #{loaded} (defined?(::WaterDrop) = #{defined?(::WaterDrop)})"
            loaded
          end

          def self.compatible?
            compatible = super && version >= MINIMUM_VERSION
            puts "🔍 [WATERDROP INTEGRATION] compatible? = #{compatible} (version: #{version}, MINIMUM: #{MINIMUM_VERSION})"
            compatible
          end

          def self.auto_instrument?
            puts "🔍 [WATERDROP INTEGRATION] auto_instrument? = true"
            true
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
