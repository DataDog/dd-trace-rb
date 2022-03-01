# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/shoryuken/ext'
require 'datadog/tracing/contrib/shoryuken/configuration/settings'
require 'datadog/tracing/contrib/shoryuken/patcher'

module Datadog
  module Tracing
    module Contrib
      module Shoryuken
        # Description of Shoryuken integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :shoryuken

          def self.version
            Gem.loaded_specs['shoryuken'] && Gem.loaded_specs['shoryuken'].version
          end

          def self.loaded?
            !defined?(::Shoryuken).nil?
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
