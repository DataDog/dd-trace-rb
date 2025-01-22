# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::Metrics::Collector do
  subject(:collector) { described_class.new }

  describe '#record_waf' do
    context 'when no results were recorded' do
      it 'contains all metrics in initial state' do
        expect(collector.waf.evals).to eq(0)
        expect(collector.waf.timeouts).to eq(0)
        expect(collector.waf.duration_ns).to eq(0)
        expect(collector.waf.duration_ext_ns).to eq(0)
      end
    end

    context 'when a single result was recorded' do
      before { collector.record_waf(result) }

      let(:result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 100, duration_ext_ns: 200
        )
      end

      it 'contains metrics of a single result' do
        expect(collector.waf.evals).to eq(1)
        expect(collector.waf.timeouts).to eq(0)
        expect(collector.waf.duration_ns).to eq(100)
        expect(collector.waf.duration_ext_ns).to eq(200)
      end
    end

    context 'when multiple results were recorded' do
      before do
        collector.record_waf(result_1)
        collector.record_waf(result_2)
      end

      let(:result_1) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 100, duration_ext_ns: 200
        )
      end

      let(:result_2) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 1000, duration_ext_ns: 1200
        )
      end

      it 'contains cumulative metrics of both results' do
        expect(collector.waf.timeouts).to eq(0)
        expect(collector.waf.duration_ns).to eq(1100)
        expect(collector.waf.duration_ext_ns).to eq(1400)
      end
    end

    context 'when multiple recorded results contain timeout' do
      before do
        collector.record_waf(result_1)
        collector.record_waf(result_2)
        collector.record_waf(result_3)
      end

      let(:result_1) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 100, duration_ext_ns: 500
        )
      end

      let(:result_2) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 400, duration_ext_ns: 1200
        )
      end

      let(:result_3) { Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 300) }

      it 'accumulates timeouts in addition to other metics' do
        expect(collector.waf.evals).to eq(3)
        expect(collector.waf.timeouts).to eq(2)
        expect(collector.waf.duration_ns).to eq(500)
        expect(collector.waf.duration_ext_ns).to eq(2000)
      end
    end
  end

  describe '#record_rasp' do
    context 'when no results were recorded' do
      it 'contains all metrics in initial state' do
        expect(collector.rasp.evals).to eq(0)
        expect(collector.rasp.timeouts).to eq(0)
        expect(collector.rasp.duration_ns).to eq(0)
        expect(collector.rasp.duration_ext_ns).to eq(0)
      end
    end

    context 'when a single result was recorded' do
      before { collector.record_rasp(result) }

      let(:result) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 100, duration_ext_ns: 200
        )
      end

      it 'contains metrics of a single result' do
        expect(collector.rasp.evals).to eq(1)
        expect(collector.rasp.timeouts).to eq(0)
        expect(collector.rasp.duration_ns).to eq(100)
        expect(collector.rasp.duration_ext_ns).to eq(200)
      end
    end

    context 'when multiple calls were made' do
      before do
        collector.record_rasp(result_1)
        collector.record_rasp(result_2)
      end

      let(:result_1) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 100, duration_ext_ns: 200
        )
      end

      let(:result_2) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 1000, duration_ext_ns: 1200
        )
      end

      it 'contains cumulative metrics of both results' do
        expect(collector.rasp.evals).to eq(2)
        expect(collector.rasp.timeouts).to eq(0)
        expect(collector.rasp.duration_ns).to eq(1100)
        expect(collector.rasp.duration_ext_ns).to eq(1400)
      end
    end

    context 'when multiple calls contain timeout' do
      before do
        collector.record_rasp(result_1)
        collector.record_rasp(result_2)
        collector.record_rasp(result_3)
      end

      let(:result_1) do
        Datadog::AppSec::SecurityEngine::Result::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 100, duration_ext_ns: 500
        )
      end

      let(:result_2) do
        Datadog::AppSec::SecurityEngine::Result::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 400, duration_ext_ns: 1200
        )
      end

      let(:result_3) { Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 300) }

      it 'accumulates timeouts in addition to other metics' do
        expect(collector.rasp.evals).to eq(3)
        expect(collector.rasp.timeouts).to eq(2)
        expect(collector.rasp.duration_ns).to eq(500)
        expect(collector.rasp.duration_ext_ns).to eq(2000)
      end
    end
  end
end
