require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sequel/configuration/settings'
require 'ddtrace/contrib/sequel/patcher'

module Datadog
  module Contrib
    module Sequel
      # Description of Sequel integration
      class Integration
        include Contrib::Integration

        APP = 'sequel'.freeze

        register_as :sequel, auto_patch: false

        def self.compatible?
          RUBY_VERSION >= '2.0.0' && defined?(::Sequel)
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
