# frozen_string_literal: true

require 'libddwaf'

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/metrics/telemetry_exporter'

RSpec.describe Datadog::AppSec::Metrics::TelemetryExporter do
  describe '.export_waf_request_metrics' do
    let(:context) do
      instance_double(
        Datadog::AppSec::Context,
        waf_runner_ruleset_version: '1.0.0',
        interrupted?: false,
        trace: trace
      )
    end

    let(:trace) { instance_double(Datadog::Tracing::TraceOperation, sampled?: true) }

    let(:waf_metrics) do
      Datadog::AppSec::Metrics::Collector::Store.new(
        evals: 0, matches: 0, errors: 0, timeouts: 0, duration_ns: 0, duration_ext_ns: 0, input_truncated_count: 0
      )
    end

    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    before do
      allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    end

    it 'exports all required tags via Telemetry' do
      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1, tags: {
          waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
          event_rules_version: '1.0.0',
          rule_triggered: 'false',
          waf_error: 'false',
          waf_timeout: 'false',
          request_blocked: 'false',
          block_failure: 'false',
          rate_limited: 'false',
          input_truncated: 'false'
        }
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets rule_triggered as "true" when metrics has non-zero count of matches' do
      waf_metrics.matches = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(rule_triggered: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets waf_error as "true" when metrics has non-zero count of errors' do
      waf_metrics.errors = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(waf_error: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets waf_timeout as "true" when metrics has non-zero count of timeouts' do
      waf_metrics.timeouts = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(waf_timeout: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets input_truncated as "true" when metrics has non-zero count of input truncations' do
      waf_metrics.input_truncated_count = 1

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(input_truncated: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets request_blocked as "true" when context is interrupted' do
      allow(context).to receive(:interrupted?).and_return(true)

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(request_blocked: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end

    it 'sets rate_limited as "true" when trace was not sampled' do
      allow(trace).to receive(:sampled?).and_return(false)

      expect(Datadog::AppSec.telemetry).to receive(:inc).with(
        Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'waf.requests', 1,
        tags: hash_including(rate_limited: 'true')
      )

      described_class.export_waf_request_metrics(waf_metrics, context)
    end
  end
end
