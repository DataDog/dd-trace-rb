require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/roda/configuration/settings'
require 'ddtrace/contrib/roda/patcher'

module Datadog
  module Contrib
    module Roda
      # Description of Roda integration
      class Integration
        include Contrib::Integration

        register_as :roda

        def self.version
          Gem.loaded_specs['roda'] && Gem.loaded_specs['roda'].version
        end

        def self.present?
          super && defined?(::Roda)
        end

        def self.compatible?
          super
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
