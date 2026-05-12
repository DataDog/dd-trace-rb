# frozen_string_literal: true

require_relative 'security_engine/engine'
require_relative 'security_engine/runner'
require_relative 'processor/rule_loader'
require_relative 'actions_handler'
require_relative 'thread_safe_ref'

module Datadog
  module AppSec
    # Core-pluggable component for AppSec
    class Component
      class << self
        def build_appsec_component(settings, telemetry:)
          return if !settings.respond_to?(:appsec) || !settings.appsec.enabled

          require_libddwaf(telemetry: telemetry)
          Datadog::AppSec::WAF.logger = Datadog.logger if Datadog.logger.debug? && settings.appsec.waf_debug

          # We want to always instrument user events when AppSec is enabled.
          # There could be cases in which users use the DD_APPSEC_ENABLED Env variable to
          # enable AppSec, in that case, Devise is already instrumented.
          # In the case that users do not use DD_APPSEC_ENABLED, we have to instrument it,
          # hence the lines above.
          devise_integration = Datadog::AppSec::Contrib::Devise::Integration.new
          settings.appsec.instrument(:devise) unless devise_integration.patcher.patched?

          security_engine = SecurityEngine::Engine.new(appsec_settings: settings.appsec, telemetry: telemetry)
          new(security_engine: security_engine)
        rescue => e
          Datadog.logger.warn("AppSec is disabled: #{e.class}: #{e.message}; there may be additional logged errors above")

          # Not reporting to telemetry here because some of the rescued exceptions
          # have already been reported by the code that raised them
          # (e.g. SecurityEngine::Engine.new reports WAF init failures).
          # TODO: reconsider whether telemetry reporting belongs here
          # (single catch-all) or in the downstream code (as it is now).
          nil
        end

        private

        def require_libddwaf(telemetry:)
          require('libddwaf')
        rescue LoadError => e
          libddwaf_platform = Gem.loaded_specs['libddwaf']&.platform || 'unknown'
          ruby_platforms = Gem.platforms.map(&:to_s)

          error_message = "libddwaf failed to load - installed platform: #{libddwaf_platform}, " \
            "ruby platforms: #{ruby_platforms}"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          raise e
        end
      end

      attr_reader :security_engine

      def initialize(security_engine:)
        @security_engine = security_engine
      end

      def reconfigure!
        security_engine&.reconfigure!
      end

      def shutdown!
        # no-op
      end
    end
  end
end
