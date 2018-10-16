require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/grape/configuration/settings'
require 'ddtrace/contrib/grape/patcher'

module Datadog
  module Contrib
    module Grape
      # Description of Grape integration
      class Integration
        include Contrib::Integration

        register_as :grape, auto_patch: true

        def self.version
          Gem.loaded_specs['grape'] && Gem.loaded_specs['grape'].version
        end

        def self.present?
          super && defined?(::Grape)
        end

        def self.compatible?
          super && defined?(::ActiveSupport::Notifications)
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
