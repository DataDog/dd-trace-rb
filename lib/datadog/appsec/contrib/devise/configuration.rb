# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # A temporary configuration module to accomodate new RFC changes.
        # NOTE: DEV-3 Remove module
        module Configuration
          MODES_CONVERSION_RULES = {
            track_user_to_auto_instrumentation: {
              AppSec::Configuration::Settings::SAFE_TRACK_USER_EVENTS_MODE =>
              AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE,
              AppSec::Configuration::Settings::EXTENDED_TRACK_USER_EVENTS_MODE =>
              AppSec::Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE
            }.freeze,
            auto_instrumentation_to_track_user: {
              AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE =>
              AppSec::Configuration::Settings::SAFE_TRACK_USER_EVENTS_MODE,
              AppSec::Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE =>
              AppSec::Configuration::Settings::EXTENDED_TRACK_USER_EVENTS_MODE
            }.freeze
          }.freeze

          module_function

          # NOTE: DEV-3 Replace method use with `auto_user_instrumentation.enabled?`
          def auto_user_instrumentation_enabled?
            appsec = Datadog.configuration.appsec
            appsec.auto_user_instrumentation.mode

            unless appsec.auto_user_instrumentation.options[:mode].default_precedence?
              return appsec.auto_user_instrumentation.enabled?
            end

            appsec.track_user_events.enabled
          end

          # NOTE: DEV-3 Replace method use with `auto_user_instrumentation.mode`
          def auto_user_instrumentation_mode
            appsec = Datadog.configuration.appsec

            # NOTE: Reading both to trigger precedence set
            appsec.auto_user_instrumentation.mode
            appsec.track_user_events.mode

            if !appsec.auto_user_instrumentation.options[:mode].default_precedence? &&
                appsec.track_user_events.options[:mode].default_precedence?
              return appsec.auto_user_instrumentation.mode
            end

            if appsec.auto_user_instrumentation.options[:mode].default_precedence?
              return MODES_CONVERSION_RULES[:track_user_to_auto_instrumentation].fetch(
                appsec.track_user_events.mode, appsec.auto_user_instrumentation.mode
              )
            end

            identification_mode = AppSec::Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE
            if appsec.auto_user_instrumentation.mode == identification_mode ||
                appsec.track_user_events.mode == AppSec::Configuration::Settings::EXTENDED_TRACK_USER_EVENTS_MODE
              return identification_mode
            end

            AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
          end

          # NOTE: Remove in next version of tracking
          def track_user_events_mode
            MODES_CONVERSION_RULES[:auto_instrumentation_to_track_user]
              .fetch(auto_user_instrumentation_mode, Datadog.configuration.appsec.track_user_events.mode)
          end
        end
      end
    end
  end
end
