require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_mailer/configuration/settings'
require 'ddtrace/contrib/action_mailer/patcher'

module Datadog
  module Contrib
    module ActionMailer
      # Description of ActionMailer integration
      class Integration
        include Contrib::Integration

        register_as :action_mailer, auto_patch: false

        def self.version
          Gem.loaded_specs['rails'] && Gem.loaded_specs['rails'].version
        end

        def self.present?
          super && defined?(::ActionMailer)
        end

        def self.compatible?
          # Rails 5 Requires Ruby 2.2.2 or higher
          return false if ENV['DISABLE_DATADOG_RAILS']
          super && defined?(::ActiveSupport::Notifications) &&
            defined?(::Rails::VERSION) && ::Rails::VERSION::MAJOR.to_i >= 5 &&
            RUBY_VERSION >= '2.2.2'
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
