require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_cable/configuration/settings'
require 'ddtrace/contrib/action_cable/patcher'

module Datadog
  module Contrib
    module ActionCable
      # Description of ActionCable integration
      class Integration
        include Contrib::Integration

        register_as :action_cable, auto_patch: false

        def self.version
          Gem.loaded_specs['rails'] && Gem.loaded_specs['rails'].version
        end

        def self.present?
          super && defined?(::ActionCable)
        end

        def self.compatible?
          return false if !ENV['DISABLE_DATADOG_RAILS']
          super && defined?(::ActiveSupport::Notifications) && defined?(::Rails::VERSION) && ::Rails::VERSION::MAJOR.to_i >= 5
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
