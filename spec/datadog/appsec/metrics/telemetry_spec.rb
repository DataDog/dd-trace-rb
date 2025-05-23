# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Metrics::Telemetry do
  before do
    stub_const('Datadog::AppSec::Ext::TELEMETRY_METRICS_NAMESPACE', 'specsec')
    stub_const('Datadog::AppSec::WAF::VERSION::BASE_STRING', '1.42.99')

    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  describe '.report_rasp' do
    context 'when reporting a match run result' do
      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does not set WAF metrics on the span' do
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.eval', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.match', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })

        described_class.report_rasp('my-type', run_result)
      end
    end

    context 'when reporting a match run result with timeout' do
      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does not set WAF metrics on the span' do
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.eval', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.match', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.timeout', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })

        described_class.report_rasp('my-type', run_result)
      end
    end

    context 'when reporting a ok run result' do
      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does not set WAF metrics on the span' do
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.eval', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })

        described_class.report_rasp('my-type', run_result)
      end
    end

    context 'when reporting a ok run result with timeout' do
      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it 'does not set WAF metrics on the span' do
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.rule.eval', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })
        expect(telemetry).to receive(:inc)
          .with('specsec', 'rasp.timeout', 1, tags: { rule_type: 'my-type', waf_version: '1.42.99' })

        described_class.report_rasp('my-type', run_result)
      end
    end

    context 'when reporting a error run result' do
      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 0)
      end

      it 'does not set WAF metrics on the span' do
        expect(telemetry).not_to receive(:inc)

        described_class.report_rasp('my-type', run_result)
      end
    end
  end
end
