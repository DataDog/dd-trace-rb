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

          # Minimum version supported by Karafka v2.3.0
          # @see Datadog::Tracing::Contrib::Karafka::Integration::MINIMUM_VERSION).
          MINIMUM_VERSION = Gem::Version.new('2.6.12')

          register_as :waterdrop, auto_patch: false

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
