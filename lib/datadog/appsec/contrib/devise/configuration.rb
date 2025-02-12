# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # A temporary configuration module to accomodate new RFC changes.
        # NOTE: DEV-3 Remove module
        module Configuration
          module_function

          # NOTE: DEV-3 Replace method use with `auto_user_instrumentation.enabled?`
          def auto_user_instrumentation_enabled?
            unless Datadog.configuration.appsec.auto_user_instrumentation.options[:mode].default_precedence?
              return Datadog.configuration.appsec.auto_user_instrumentation.enabled?
            end

            Datadog.configuration.appsec.track_user_events.enabled
          end

          # NOTE: DEV-3 Replace method use with `auto_user_instrumentation.mode`
          def auto_user_instrumentation_mode
            unless Datadog.configuration.appsec.auto_user_instrumentation.options[:mode].default_precedence?
              return Datadog.configuration.appsec.auto_user_instrumentation.mode
            end

            case Datadog.configuration.appsec.track_user_events.mode
            when AppSec::Configuration::Settings::SAFE_TRACK_USER_EVENTS_MODE
              AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
            when AppSec::Configuration::Settings::EXTENDED_TRACK_USER_EVENTS_MODE
              AppSec::Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE
            else
              Datadog.configuration.appsec.auto_user_instrumentation.mode
            end
          end
        end
      end
    end
  end
end
