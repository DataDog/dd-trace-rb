require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rack/configuration/settings'
require 'ddtrace/contrib/rack/patcher'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module Rack
      # Description of Rack integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.1.0')

        register_as :rack, auto_patch: false

        def self.version
          Gem.loaded_specs['rack'] && Gem.loaded_specs['rack'].version
        end

        def self.loaded?
          !defined?(::Rack).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Datadog::Contrib::Rails::Utils.railtie_supported?
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
