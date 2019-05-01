require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_support/configuration/settings'
require 'ddtrace/contrib/active_support/patcher'

module Datadog
  module Contrib
    module ActiveSupport
      # Describes the ActiveSupport integration
      class Integration
        include Contrib::Integration

        register_as :active_support, auto_patch: false

        def self.version
          Gem.loaded_specs['activesupport'] && Gem.loaded_specs['activesupport'].version
        end

        def self.present?
          super && defined?(::ActiveSupport)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.0')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          ActiveSupport::Patcher
        end
      end
    end
  end
end
