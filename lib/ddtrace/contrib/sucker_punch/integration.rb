require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sucker_punch/configuration/settings'
require 'ddtrace/contrib/sucker_punch/patcher'

module Datadog
  module Contrib
    module SuckerPunch
      # Description of SuckerPunch integration
      class Integration
        include Contrib::Integration

        register_as :sucker_punch, auto_patch: true

        def self.version
          Gem.loaded_specs['sucker_punch'] && Gem.loaded_specs['sucker_punch'].version
        end

        def self.loaded?
          defined?(::SuckerPunch)
        end

        def self.compatible?
          super && version >= Gem::Version.new('2.0.0')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
