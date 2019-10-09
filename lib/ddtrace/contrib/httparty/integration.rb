require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/httparty/configuration/settings'
require 'ddtrace/contrib/httparty/patcher'

module Datadog
  module Contrib
    module HTTParty
      # Description of HTTParty integration
      class Integration
        include Contrib::Integration
        register_as :httparty

        def self.version
          Gem.loaded_specs['httparty'] && Gem.loaded_specs['httparty'].version
        end

        def self.present?
          super && defined?(::HTTParty)
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
