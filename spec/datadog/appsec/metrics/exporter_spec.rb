# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/metrics/exporter'

RSpec.describe Datadog::AppSec::Metrics::Exporter do
  describe '.export' do
    let(:context) { instance_double(Datadog::AppSec::Context, span: span, metrics: metrics) }
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:metrics) { instance_double(Datadog::AppSec::Metrics::Collector) }
    let(:empty_store) do
      Datadog::AppSec::Metrics::Collector::Store.new(
        evals: 0, timeouts: 0, duration_ns: 0, duration_ext_ns: 0
      )
    end

    context 'when no waf or rasp metrics were recorded' do
      before do
        allow(metrics).to receive(:waf).and_return(empty_store)
        allow(metrics).to receive(:rasp).and_return(empty_store)
      end

      it 'does not set metrics on the span' do
        expect(span).not_to receive(:set_tag)

        described_class.export_from(context)
      end
    end

    context 'when waf metrics present' do
      before do
        allow(metrics).to receive(:waf).and_return(waf_store)
        allow(metrics).to receive(:rasp).and_return(empty_store)
      end

      let(:waf_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 10, timeouts: 5, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'set waf metrics on the span' do
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.timeouts', 5)
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.waf.duration_ext', 2.0)

        described_class.export_from(context)
      end
    end

    context 'when rasp metrics present' do
      before do
        allow(metrics).to receive(:waf).and_return(empty_store)
        allow(metrics).to receive(:rasp).and_return(rasp_store)
      end

      let(:rasp_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 10, timeouts: 5, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'set waf metrics on the span' do
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.rule.eval', 10)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.timeout', 1)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration_ext', 2.0)

        described_class.export_from(context)
      end
    end

    context 'when rasp metrics present with no timeouts' do
      before do
        allow(metrics).to receive(:waf).and_return(empty_store)
        allow(metrics).to receive(:rasp).and_return(rasp_store)
      end

      let(:rasp_store) do
        Datadog::AppSec::Metrics::Collector::Store.new(
          evals: 3, timeouts: 0, duration_ns: 1000, duration_ext_ns: 2000
        )
      end

      it 'set waf metrics on the span without timeout metric' do
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.rule.eval', 3)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration', 1.0)
        expect(span).to receive(:set_tag).with('_dd.appsec.rasp.duration_ext', 2.0)

        described_class.export_from(context)
      end
    end
  end
end
