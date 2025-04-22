# frozen_string_literal: true

require_relative 'result'

module Datadog
  module AppSec
    module SecurityEngine
      # A class that check input via security engine (WAF) and respond with result.
      class Runner
        SUCCESSFUL_EXECUTION_CODES = [:ok, :match].freeze

        def initialize(handle, telemetry:)
          @mutex = Mutex.new
          @context = WAF::Context.new(handle)
          @telemetry = telemetry

          @debug_tag = "libddwaf:#{WAF::VERSION::STRING} method:ddwaf_run"
        end

        def run(persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
          @mutex.lock

          start_ns = Core::Utils::Time.get_time(:nanosecond)
          persistent_data.reject! do |_, v|
            next false if v.is_a?(TrueClass) || v.is_a?(FalseClass)

            v.nil? || v.empty?
          end

          ephemeral_data.reject! do |_, v|
            next false if v.is_a?(TrueClass) || v.is_a?(FalseClass)

            v.nil? || v.empty?
          end

          _code, result = try_run(persistent_data, ephemeral_data, timeout)
          stop_ns = Core::Utils::Time.get_time(:nanosecond)

          report_execution(result)

          unless SUCCESSFUL_EXECUTION_CODES.include?(result.status)
            return Result::Error.new(duration_ext_ns: stop_ns - start_ns)
          end

          klass = result.status == :match ? Result::Match : Result::Ok
          klass.new(
            events: result.events,
            actions: result.actions,
            derivatives: result.derivatives,
            timeout: result.timeout,
            duration_ns: result.total_runtime,
            duration_ext_ns: (stop_ns - start_ns)
          )
        ensure
          @mutex.unlock
        end

        def finalize
          @context.finalize
        end

        private

        def try_run(persistent_data, ephemeral_data, timeout)
          @context.run(persistent_data, ephemeral_data, timeout)
        rescue WAF::LibDDWAF::Error => e
          Datadog.logger.debug { "#{@debug_tag} execution error: #{e} backtrace: #{e.backtrace&.first(3)}" }
          @telemetry.report(e, description: 'libddwaf-rb internal low-level error')

          [:err_internal, WAF::Result.new(:err_internal, [], 0, false, [], [])]
        end

        def report_execution(result)
          Datadog.logger.debug { "#{@debug_tag} execution timed out: #{result.inspect}" } if result.timeout

          if SUCCESSFUL_EXECUTION_CODES.include?(result.status)
            Datadog.logger.debug { "#{@debug_tag} execution result: #{result.inspect}" }
          else
            message = "#{@debug_tag} execution error: #{result.status.inspect}"

            Datadog.logger.debug { message }
            @telemetry.error(message)
          end
        end
      end
    end
  end
end
