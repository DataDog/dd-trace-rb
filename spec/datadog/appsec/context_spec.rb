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

        Array.new(3) { context.run_waf(persistent_data, {}, 1_000_000) }
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
          context.run_waf(persistent_data_1, {}, 1_000_000),
          context.run_waf(persistent_data_2, {}, 1_000_000),
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

  describe '#run_rasp' do
    context 'when a matching run was made' do
      before { allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry) }

      let(:persistent_data) do
        { 'server.request.query' => { 'q' => "1' OR 1=1;" } }
      end
      let(:ephemeral_data) do
        {
          'server.db.statement' => "SELECT * FROM users WHERE name = '1' OR 1=1;",
          'server.db.system' => 'mysql'
        }
      end

      it 'sends telemetry metrics' do
        expect(telemetry).to receive(:inc)
          .with('appsec', anything, kind_of(Integer), anything)
          .at_least(:once)

        context.run_rasp('sqli', persistent_data, ephemeral_data, 1_000_000)
      end
    end

    context 'when a run was a failure' do
      before do
        allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
        allow_any_instance_of(Datadog::AppSec::SecurityEngine::Runner).to receive(:run)
          .and_return(run_result)
      end

      let(:run_result) do
        Datadog::AppSec::SecurityEngine::Result::Error.new(duration_ext_ns: 0)
      end
      let(:persistent_data) do
        { 'server.request.query' => { 'q' => "1' OR 1=1;" } }
      end
      let(:ephemeral_data) do
        {
          'server.db.statement' => "SELECT * FROM users WHERE name = '1' OR 1=1;",
          'server.db.system' => 'mysql'
        }
      end

      it 'sends telemetry metrics' do
        expect(telemetry).not_to receive(:inc)

        context.run_rasp('sqli', persistent_data, ephemeral_data, 1_000_000)
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

  describe '#export_metrics' do
    context 'when span is not present' do
      let(:context) { described_class.new(trace, nil, processor) }

      it 'does not export metrics' do
        expect(Datadog::AppSec::Metrics::Exporter).not_to receive(:export_waf_metrics)
        expect(Datadog::AppSec::Metrics::Exporter).not_to receive(:export_rasp_metrics)

        context.export_metrics
      end
    end

    context 'when span is present' do
      it 'exports the metrics' do
        expect(Datadog::AppSec::Metrics::Exporter).to receive(:export_waf_metrics)
        expect(Datadog::AppSec::Metrics::Exporter).to receive(:export_rasp_metrics)

        context.export_metrics
      end
    end
  end
end
