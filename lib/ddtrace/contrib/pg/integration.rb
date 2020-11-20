require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/pg/configuration/settings'
require 'ddtrace/contrib/pg/patcher'

module Datadog
  module Contrib
    module Pg
      # Description of PG integration
      class Integration
        include Contrib::Integration

        register_as :pg

        def self.version
          Gem.loaded_specs['pg'] && Gem.loaded_specs['pg'].version
        end

        def self.present?
          super && defined?(::PG)
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
