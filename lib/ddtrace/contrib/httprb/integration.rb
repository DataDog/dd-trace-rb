require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/httprb/configuration/settings'
require 'ddtrace/contrib/httprb/patcher'

module Datadog
  module Contrib
    module Httprb
      # Description of Httprb integration
      class Integration
        include Contrib::Integration
        register_as :httprb

        def self.version
          Gem.loaded_specs['http'] && Gem.loaded_specs['http'].version
        end

        def self.present?
          super && defined?(::HTTP::Client)
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
