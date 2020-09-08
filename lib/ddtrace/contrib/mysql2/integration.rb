require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/mysql2/configuration/settings'
require 'ddtrace/contrib/mysql2/patcher'

module Datadog
  module Contrib
    module Mysql2
      # Description of Mysql2 integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.3.21')

        register_as :mysql2

        def self.version
          Gem.loaded_specs['mysql2'] && Gem.loaded_specs['mysql2'].version
        end

        def self.loaded?
          !defined?(::Mysql2).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
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
