# frozen_string_literal: true

module Datadog
  module AppSec
    # Processor integrates libddwaf into datadog/appsec
    class Processor
      # Context manages a sequence of runs
      class Context
        attr_reader :time_ns, :time_ext_ns, :timeouts, :events

        def initialize(processor)
          @context = Datadog::AppSec::WAF::Context.new(processor.send(:handle))
          @time_ns = 0.0
          @time_ext_ns = 0.0
          @timeouts = 0
          @events = []
          @run_mutex = Mutex.new
        end

        def run(input, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
          @run_mutex.lock

          start_ns = Core::Utils::Time.get_time(:nanosecond)

          input.reject! do |_, v|
            case v
            when TrueClass, FalseClass
              false
            else
              v.nil? ? true : v.empty?
            end
          end

          _code, res = @context.run(input, timeout)

          stop_ns = Core::Utils::Time.get_time(:nanosecond)

          # these updates are not thread safe and should be protected
          @time_ns += res.total_runtime
          @time_ext_ns += (stop_ns - start_ns)
          @timeouts += 1 if res.timeout

          res
        ensure
          @run_mutex.unlock
        end

        def extract_schema
          return unless extract_schema?

          input = {
            'waf.context.processor' => {
              'extract-schema' => true
            }
          }

          _code, res = @context.run(input, WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)

          res
        end

        def finalize
          @context.finalize
        end

        private

        def extract_schema?
          Datadog.configuration.appsec.api_security.enabled &&
            Datadog.configuration.appsec.api_security.sample_rate.sample?
        end
      end

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
