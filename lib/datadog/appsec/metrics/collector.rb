# frozen_string_literal: true

module Datadog
  module AppSec
    module Metrics
      # A class responsible for collecting WAF and RASP call metrics.
      class Collector
        Store = Struct.new(
          :evals,
          :matches,
          :errors,
          :timeouts,
          :duration_ns,
          :duration_ext_ns,
          :inputs_truncated,
          :downstream_requests,
          keyword_init: true
        )

        attr_reader :waf, :rasp

        def initialize
          @mutex = Mutex.new

          @waf = Store.new(
            evals: 0, matches: 0, errors: 0, timeouts: 0, duration_ns: 0,
            duration_ext_ns: 0, inputs_truncated: 0, downstream_requests: 0
          )

          @rasp = Store.new(
            evals: 0, matches: 0, errors: 0, timeouts: 0, duration_ns: 0,
            duration_ext_ns: 0, inputs_truncated: 0, downstream_requests: 0
          )
        end

        def record_waf(result)
          @mutex.synchronize do
            @waf.evals += 1
            @waf.matches += 1 if result.match?
            @waf.errors += 1 if result.error?
            @waf.timeouts += 1 if result.timeout?
            @waf.duration_ns += result.duration_ns
            @waf.duration_ext_ns += result.duration_ext_ns
            @waf.inputs_truncated += 1 if result.input_truncated?
          end
        end

        def record_rasp(result, type:)
          @mutex.synchronize do
            @rasp.evals += 1
            @waf.matches += 1 if result.match?
            @waf.errors += 1 if result.error?
            @rasp.timeouts += 1 if result.timeout?
            @rasp.duration_ns += result.duration_ns
            @rasp.duration_ext_ns += result.duration_ext_ns
            @rasp.inputs_truncated += 1 if result.input_truncated?
            @rasp.downstream_requests += 1 if type == Ext::RASP_SSRF
          end
        end
      end
    end
  end
end
