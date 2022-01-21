# typed: false
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

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :action_mailer, auto_patch: false

        def self.version
          Gem.loaded_specs['actionmailer'] && Gem.loaded_specs['actionmailer'].version
        end

        def self.loaded?
          !defined?(::ActionMailer).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION && !defined?(::ActiveSupport::Notifications).nil?
        end

        # enabled by rails integration so should only auto instrument
        # if detected that it is being used without rails
        def auto_instrument?
          !Datadog::Contrib::Rails::Utils.railtie_supported?
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          ActionMailer::Patcher
        end
      end
    end
  end
end
