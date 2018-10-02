require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/mysql2/configuration/settings'
require 'ddtrace/contrib/mysql2/patcher'

module Datadog
  module Contrib
    module Mysql2
      # Description of Mysql2 integration
      class Integration
        include Contrib::Integration

        register_as :mysql2

        def self.version
          Gem.loaded_specs['mysql2'] && Gem.loaded_specs['mysql2'].version
        end

        def self.present?
          super && defined?(::Mysql2)
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
