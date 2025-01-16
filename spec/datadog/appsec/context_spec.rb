# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'
require 'datadog/appsec/processor/rule_loader'
require 'datadog/appsec/processor/rule_merger'

RSpec.describe Datadog::AppSec::Context do
  let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }
  let(:context) { described_class.new(trace, span, processor) }

  after do
    described_class.deactivate
    processor.finalize
  end

  describe '.active' do
    context 'when no active context is set' do
      it { expect(described_class.active).to be_nil }
    end

    context 'when active context is set' do
      before { described_class.activate(context) }

      it { expect(described_class.active).to eq(context) }
    end
  end

  describe '.activate' do
    it { expect { described_class.activate(double) }.to raise_error(ArgumentError) }

    context 'when no active context is set' do
      it { expect { described_class.activate(context) }.to change { described_class.active }.from(nil).to(context) }
    end

    context 'when active context is already set' do
      before { described_class.activate(context) }

      subject(:activate_context) { described_class.activate(described_class.new(trace, span, processor)) }

      it 'raises an error and does not change the active context' do
        expect { activate_context }.to raise_error(Datadog::AppSec::Context::ActiveContextError)
          .and(not_change { described_class.active })
      end
    end
  end

  describe '.deactivate' do
    context 'when no active context is set' do
      it 'does not change the active context' do
        expect { described_class.deactivate }.to_not(change { described_class.active })
      end
    end

    context 'when active context is set' do
      before do
        described_class.activate(context)
        expect(context).to receive(:finalize).and_call_original
      end

      it 'unsets the active context' do
        expect { described_class.deactivate }.to change { described_class.active }.from(context).to(nil)
      end
    end

    context 'when error happen during deactivation' do
      before do
        described_class.activate(context)
        expect(context).to receive(:finalize).and_raise(RuntimeError.new('Ooops'))
      end

      it 'raises underlying exception and unsets the active context' do
        expect { described_class.deactivate }.to raise_error(RuntimeError)
          .and(change { described_class.active }.from(context).to(nil))
      end
    end
  end

  describe '#run_waf' do
    context 'when multiple same matching runs were made within a single context' do
      let!(:run_results) do
        persistent_data = {
          'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' }
        }

        Array.new(3) { context.run_waf(persistent_data, {}, 10_000) }
      end

      it 'returns a single match and rest is ok' do
        expect(run_results).to match_array(
          [
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Ok),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Ok)
          ]
        )
      end
    end

    context 'when multiple different matching runs were made within a single context' do
      let!(:run_results) do
        persistent_data_1 = { 'server.request.query' => { 'q' => '1 OR 1;' } }
        persistent_data_2 = {
          'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' }
        }

        [
          context.run_waf(persistent_data_1, {}, 10_000),
          context.run_waf(persistent_data_2, {}, 10_000),
        ]
      end

      it 'returns a single match and rest is ok' do
        expect(run_results).to match_array(
          [
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match),
            kind_of(Datadog::AppSec::SecurityEngine::Result::Match)
          ]
        )
      end
    end
  end

  describe '#extract_schema' do
    it 'calls the waf runner with specific addresses' do
      expect_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:run)
        .with({ 'waf.context.processor' => { 'extract-schema' => true } }, {})
        .and_call_original

      expect(context.extract_schema).to be_instance_of(Datadog::AppSec::SecurityEngine::Result::Ok)
    end
  end

  describe '#waf_metrics' do
    context 'when multiple calls were successful' do
      let!(:run_results) do
        persistent_data = {
          'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' }
        }
        Array.new(3) { context.run_waf(persistent_data, {}, 10_000) }
      end

      it 'returns metrics containing 0 timeouts and cumulative durations' do
        expect(context.waf_metrics.timeouts).to eq(0)
        expect(context.waf_metrics.duration_ns).to be > 0
        expect(context.waf_metrics.duration_ext_ns).to be > 0
        expect(context.waf_metrics.duration_ns).to eq(run_results.sum(&:duration_ns))
        expect(context.waf_metrics.duration_ext_ns).to eq(run_results.sum(&:duration_ext_ns))
      end
    end

    context 'when multiple calls have timeouts' do
      let!(:run_results) do
        persistent_data = {
          'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' }
        }
        Array.new(5) { context.run_waf(persistent_data, {}, 0) }
      end

      it 'returns metrics containing 5 timeouts and cumulative durations' do
        expect(context.waf_metrics.timeouts).to eq(5)
        expect(context.waf_metrics.duration_ns).to eq(0)
        expect(context.waf_metrics.duration_ext_ns).to eq(run_results.sum(&:duration_ext_ns))
      end
    end
  end
end
