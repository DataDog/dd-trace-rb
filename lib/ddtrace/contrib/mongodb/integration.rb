require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/mongodb/configuration/settings'
require 'ddtrace/contrib/mongodb/patcher'

module Datadog
  module Contrib
    module MongoDB
      # Description of MongoDB integration
      class Integration
        include Contrib::Integration

        register_as :mongo, auto_patch: true

        def self.version
          Gem.loaded_specs['mongo'] && Gem.loaded_specs['mongo'].version
        end

        def self.loaded?
          defined?(::Mongo::Monitoring::Global)
        end

        def self.compatible?
          super && version >= Gem::Version.new('2.1.0')
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
