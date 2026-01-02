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

          # WaterDrop added class-level instrumentation in version 2.8.8.rc1
          MINIMUM_VERSION = Gem::Version.new('2.8.8.rc1')

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

          def resolver
            @resolver ||= Contrib::Configuration::Resolvers::PatternResolver.new
          end
        end
      end
    end
  end
end
