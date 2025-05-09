# frozen_string_literal: true

require_relative 'processor'
require_relative 'processor/rule_merger'
require_relative 'processor/rule_loader'
require_relative 'actions_handler'

module Datadog
  module AppSec
    # Core-pluggable component for AppSec
    class Component
      class << self
        def build_appsec_component(settings, telemetry:)
          return if !settings.respond_to?(:appsec) || !settings.appsec.enabled

          ffi_version = Gem.loaded_specs['ffi'] && Gem.loaded_specs['ffi'].version
          unless ffi_version
            Datadog.logger.warn('FFI gem is not loaded, AppSec will be disabled.')
            telemetry.error('AppSec: Component not loaded, due to missing FFI gem')

            return
          end

          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3') && ffi_version < Gem::Version.new('1.16.0')
            Datadog.logger.warn(
              'AppSec is not supported in Ruby versions above 3.3.0 when using `ffi` versions older than 1.16.0, ' \
              'and will be forcibly disabled due to a memory leak in `ffi`. ' \
              'Please upgrade your `ffi` version to 1.16.0 or higher.'
            )
            telemetry.error('AppSec: Component not loaded, ffi version is leaky with ruby > 3.3.0')

            return
          end

          processor = create_processor(settings, telemetry)

          # We want to always instrument user events when AppSec is enabled.
          # There could be cases in which users use the DD_APPSEC_ENABLED Env variable to
          # enable AppSec, in that case, Devise is already instrumented.
          # In the case that users do not use DD_APPSEC_ENABLED, we have to instrument it,
          # hence the lines above.
          devise_integration = Datadog::AppSec::Contrib::Devise::Integration.new
          settings.appsec.instrument(:devise) unless devise_integration.patcher.patched?

          new(processor, telemetry)
        end

        private

        def create_processor(settings, telemetry)
          rules = AppSec::Processor::RuleLoader.load_rules(
            telemetry: telemetry,
            ruleset: settings.appsec.ruleset
          )
          return nil unless rules

          data = AppSec::Processor::RuleLoader.load_data(
            ip_denylist: settings.appsec.ip_denylist,
            user_id_denylist: settings.appsec.user_id_denylist,
          )

          exclusions = AppSec::Processor::RuleLoader.load_exclusions(ip_passlist: settings.appsec.ip_passlist)

          # NOTE: This is a temporary solution before the RuleMerger refactoring
          #       with new RemoteConfig setup
          processors = rules['processors']
          scanners = rules['scanners']

          ruleset = AppSec::Processor::RuleMerger.merge(
            rules: [rules],
            data: data,
            scanners: scanners,
            processors: processors,
            exclusions: exclusions,
            telemetry: telemetry
          )

          processor = Processor.new(ruleset: ruleset, telemetry: telemetry)
          return nil unless processor.ready?

          processor
        end
      end

      attr_reader :processor, :telemetry

      def initialize(processor, telemetry)
        @processor = processor
        @telemetry = telemetry

        @mutex = Mutex.new
      end

      def reconfigure(ruleset:, telemetry:)
        @mutex.synchronize do
          new_processor = Processor.new(ruleset: ruleset, telemetry: telemetry)

          if new_processor && new_processor.ready?
            old_processor = @processor

            @telemetry = telemetry
            @processor = new_processor

            old_processor.finalize if old_processor
          end
        end
      end

      def reconfigure_lock(&block)
        @mutex.synchronize(&block)
      end

      def shutdown!
        @mutex.synchronize do
          if processor && processor.ready?
            processor.finalize
            @processor = nil
          end
        end
      end
    end
  end
end
