require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rack/configuration/settings'
require 'ddtrace/contrib/rack/patcher'

module Datadog
  module Contrib
    module Rack
      # Description of Rack integration
      class Integration
        include Contrib::Integration

        APP = 'rack'.freeze

        register_as :rack, auto_patch: false

        def self.version
          Gem.loaded_specs['rack'] && Gem.loaded_specs['rack'].version
        end

        def self.present?
          super && defined?(::Rack)
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
