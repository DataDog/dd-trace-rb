require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sequel/configuration/settings'
require 'ddtrace/contrib/sequel/patcher'

module Datadog
  module Contrib
    module Sequel
      # Description of Sequel integration
      class Integration
        include Contrib::Integration

        register_as :sequel, auto_patch: false

        def self.version
          Gem.loaded_specs['sequel'] && Gem.loaded_specs['sequel'].version
        end

        def self.loaded?
          defined?(::Sequel)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.41')
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
