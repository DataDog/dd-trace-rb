# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/metrics/exporter'

RSpec.describe Datadog::AppSec::Metrics::Exporter do
  describe '.export' do
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:empty_store) do
      Datadog::AppSec::Metrics::Collector::Store.new(
        evals: 0, timeouts: 0, duration_ns: 0, duration_ext_ns: 0
      )
    end

    context 'when no WAF or RASP metrics were recorded' do
      it 'does not set WAF metrics on the span' do
        expect(span).not_to receive(:set_tag)

        described_class.export_waf_metrics(empty_store, span)
      end

      it 'does not set RASP metrics on the span' do
        expect(span).not_to receive(:set_tag)

        described_class.export_rasp_metrics(empty_store, span)
      end
    end

    context 'when waf metrics present' do
      let(:waf_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 10, timeouts: 5, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'sets WAF metrics on the span' do
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.timeouts', 5)
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.duration_ext', 2.0)

        described_class.export_waf_metrics(waf_store, span)
      end
    end

    context 'when RASP metrics present' do
      let(:rasp_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 10, timeouts: 5, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'sets waf metrics on the span' do
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.rule.eval', 10)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.timeout', 1)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration_ext', 2.0)

        described_class.export_rasp_metrics(rasp_store, span)
      end
    end

    context 'when RASP metrics present with no timeouts' do
      let(:rasp_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 3, timeouts: 0, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'sets waf metrics on the span without timeout metric' do
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.rule.eval', 3)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration_ext', 2.0)

        described_class.export_rasp_metrics(rasp_store, span)
      end
    end
  end
end
