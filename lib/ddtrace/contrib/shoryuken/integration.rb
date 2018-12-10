require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/shoryuken/ext'
require 'ddtrace/contrib/shoryuken/configuration/settings'
require 'ddtrace/contrib/shoryuken/patcher'

module Datadog
  module Contrib
    module Shoryuken
      # Description of Shoryuken integration
      class Integration
        include Contrib::Integration

        register_as :shoryuken

        class << self
          def version
            Gem.loaded_specs['shoryuken'] && Gem.loaded_specs['shoryuken'].version
          end

          def present?
            super && defined?(::Shoryuken)
          end
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
