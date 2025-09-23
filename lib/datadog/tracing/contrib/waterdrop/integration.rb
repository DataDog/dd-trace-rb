# frozen_string_literal: true

puts "🔍 [WATERDROP INTEGRATION] Loading WaterDrop integration file..."

require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

puts "🔍 [WATERDROP INTEGRATION] Required files loaded"

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Description of WaterDrop integration
        class Integration
          include Contrib::Integration

          puts "🔍 [WATERDROP INTEGRATION] Integration class defined"

          # Minimum version of the WaterDrop library that we support
          MINIMUM_VERSION = Gem::Version.new('2.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :waterdrop, auto_patch: true

          puts "🔍 [WATERDROP INTEGRATION] Registered as :waterdrop with auto_patch: true"

          def self.gem_name
            'waterdrop'
          end

          def self.version
            Gem.loaded_specs['waterdrop']&.version
          end

          def self.loaded?
            !defined?(::WaterDrop).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
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
