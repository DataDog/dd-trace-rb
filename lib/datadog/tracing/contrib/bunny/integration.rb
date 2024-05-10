# frozen_string_literal: true

require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Bunny
        # Description of Trilogy integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :bunny

          def self.version
            Gem.loaded_specs['bunny'] && Gem.loaded_specs['bunny'].version
          end

          def self.loaded?
            !defined?(::Bunny).nil?
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
