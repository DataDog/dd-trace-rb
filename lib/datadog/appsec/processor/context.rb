# frozen_string_literal: true

module Datadog
  module AppSec
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
    end
  end
end
