require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/redis/configuration/settings'
require 'ddtrace/contrib/redis/patcher'

module Datadog
  module Contrib
    module Redis
      # Description of Redis integration
      class Integration
        include Contrib::Integration

        register_as :redis, auto_patch: true

        def self.version
          Gem.loaded_specs['redis'] && Gem.loaded_specs['redis'].version
        end

        def self.loaded?
          defined?(::Redis)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.2')
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
