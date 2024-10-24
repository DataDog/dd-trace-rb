# frozen_string_literal: true

module Datadog
  module AppSec
    # Processor integrates libddwaf into datadog/appsec
    class Processor
      attr_reader :diagnostics, :addresses

      def initialize(ruleset:, telemetry:)
        @diagnostics = nil
        @addresses = []
        settings = Datadog.configuration.appsec
        @telemetry = telemetry

        # TODO: Refactor to make it easier to test
        unless require_libddwaf && libddwaf_provides_waf? && create_waf_handle(settings, ruleset)
          Datadog.logger.warn('AppSec is disabled, see logged errors above')
        end
      end

      def ready?
        !@handle.nil?
      end

      def finalize
        @handle.finalize
      end

      protected

      attr_reader :handle

      private

      # libddwaf raises a LoadError on unsupported platforms; it may at some
      # point succeed in being required yet not provide a specific needed feature.
      def require_libddwaf
        Datadog.logger.debug { "libddwaf platform: #{libddwaf_platform}" }

        require 'libddwaf'

        true
      rescue LoadError => e
        Datadog.logger.error do
          'libddwaf failed to load,' \
            "installed platform: #{libddwaf_platform} ruby platforms: #{ruby_platforms} error: #{e.inspect}"
        end
        @telemetry.report(e, description: 'libddwaf failed to load')

        false
      end

      # check whether libddwaf is required *and* able to provide the needed feature
      def libddwaf_provides_waf?
        defined?(Datadog::AppSec::WAF) ? true : false
      end

      def create_waf_handle(settings, ruleset)
        # TODO: this may need to be reset if the main Datadog logging level changes after initialization
        Datadog::AppSec::WAF.logger = Datadog.logger if Datadog.logger.debug? && settings.waf_debug

        obfuscator_config = {
          key_regex: settings.obfuscator_key_regex,
          value_regex: settings.obfuscator_value_regex,
        }

        @handle = Datadog::AppSec::WAF::Handle.new(ruleset, obfuscator: obfuscator_config)
        @diagnostics = @handle.diagnostics
        @addresses = @handle.required_addresses

        true
      rescue WAF::LibDDWAF::Error => e
        Datadog.logger.error do
          "libddwaf failed to initialize, error: #{e.inspect}"
        end
        @telemetry.report(e, description: 'libddwaf failed to initialize')

        @diagnostics = e.diagnostics if e.diagnostics

        false
      rescue StandardError => e
        Datadog.logger.error do
          "libddwaf failed to initialize, error: #{e.inspect}"
        end
        @telemetry.report(e, description: 'libddwaf failed to initialize')

        false
      end

      def libddwaf_platform
        if Gem.loaded_specs['libddwaf']
          Gem.loaded_specs['libddwaf'].platform.to_s
        else
          'unknown'
        end
      end

      def ruby_platforms
        Gem.platforms.map(&:to_s)
      end
    end
  end
end
