# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/sucker_punch/configuration/settings'
require 'datadog/tracing/contrib/sucker_punch/patcher'

module Datadog
  module Tracing
    module Contrib
      module SuckerPunch
        # Description of SuckerPunch integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.0.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :sucker_punch, auto_patch: true

          def self.version
            Gem.loaded_specs['sucker_punch'] && Gem.loaded_specs['sucker_punch'].version
          end

          def self.loaded?
            !defined?(::SuckerPunch).nil?
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
