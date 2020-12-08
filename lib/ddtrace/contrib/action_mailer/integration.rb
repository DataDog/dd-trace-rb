require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_mailer/configuration/settings'
require 'ddtrace/contrib/action_mailer/patcher'

module Datadog
  module Contrib
    module ActionMailer
      # Description of ActionMailer integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('5.0.0')

        register_as :action_mailer, auto_patch: false

        def self.version
          Gem.loaded_specs['actionmailer'] && Gem.loaded_specs['actionmailer'].version
        end

        def self.loaded?
          !defined?(::ActionMailer).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION && defined?(::ActiveSupport::Notifications)
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
