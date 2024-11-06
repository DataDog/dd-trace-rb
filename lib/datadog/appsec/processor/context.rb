# frozen_string_literal: true

module Datadog
  module AppSec
    class Processor
      # Context manages a sequence of runs
      class Context
        LIBDDWAF_SUCCESSFUL_EXECUTION_CODES = [:ok, :match].freeze

        attr_reader :time_ns, :time_ext_ns, :timeouts, :events

        def initialize(handle, telemetry:)
          @context = WAF::Context.new(handle)
          @telemetry = telemetry

          @time_ns = 0.0
          @time_ext_ns = 0.0
          @timeouts = 0
          @events = []
          @run_mutex = Mutex.new

          @libddwaf_debug_tag = "libddwaf:#{WAF::VERSION::STRING}"
        end

        def run(persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
          @run_mutex.lock

          start_ns = Core::Utils::Time.get_time(:nanosecond)

          persistent_data.reject! do |_, v|
            next false if v.is_a?(TrueClass) || v.is_a?(FalseClass)

            v.nil? ? true : v.empty?
          end

          ephemeral_data.reject! do |_, v|
            next false if v.is_a?(TrueClass) || v.is_a?(FalseClass)

            v.nil? ? true : v.empty?
          end

          _code, result = try_run(persistent_data, ephemeral_data, timeout)

          stop_ns = Core::Utils::Time.get_time(:nanosecond)

          # these updates are not thread safe and should be protected
          @time_ns += result.total_runtime
          @time_ext_ns += (stop_ns - start_ns)
          @timeouts += 1 if result.timeout

          report_execution(result)
          result
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

          _code, result = try_run(input, {}, WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)

          report_execution(result)
          result
        end

        def finalize
          @context.finalize
        end

        private

        def try_run(persistent_data, ephemeral_data, timeout)
          @context.run(persistent_data, ephemeral_data, timeout)
        rescue WAF::LibDDWAF::Error => e
          Datadog.logger.debug { "#{@libddwaf_debug_tag} execution error: #{e} backtrace: #{e.backtrace&.first(3)}" }
          @telemetry.report(e, description: 'libddwaf internal low-level error')

          [:err_internal, WAF::Result.new(:err_internal, [], 0.0, false, [], [])]
        end

        def report_execution(result)
          Datadog.logger.debug { "#{@libddwaf_debug_tag} execution timed out: #{result.inspect}" } if result.timeout

          if LIBDDWAF_SUCCESSFUL_EXECUTION_CODES.include?(result.status)
            Datadog.logger.debug { "#{@libddwaf_debug_tag} execution result: #{result.inspect}" }
          else
            message = "#{@libddwaf_debug_tag} execution error: #{result.status.inspect}"

            Datadog.logger.debug { message }
            @telemetry.error(message)
          end
        end

        def extract_schema?
          Datadog.configuration.appsec.api_security.enabled &&
            Datadog.configuration.appsec.api_security.sample_rate.sample?
        end
      end
    end
  end
end
