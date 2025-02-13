# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'
require 'datadog/appsec/processor/rule_loader'
require 'datadog/appsec/processor/rule_merger'

RSpec.describe Datadog::AppSec::SecurityEngine::Runner do
  before do
    # NOTE: This is an intermediate step and will be removed
    rules = Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry)
    ruleset = Datadog::AppSec::Processor::RuleMerger.merge(rules: [rules], telemetry: telemetry)
    Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry)

    allow(Datadog::AppSec::WAF::Context).to receive(:new).and_return(waf_context)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:waf_handle) { instance_double(Datadog::AppSec::WAF::Handle) }
  let(:waf_context) { instance_double(Datadog::AppSec::WAF::Context) }

  subject(:runner) { described_class.new(waf_handle, telemetry: telemetry) }

  describe '#run' do
    context 'when keys contain values to clean' do
      let(:result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :ok,
          events: [],
          actions: {},
          derivatives: {},
          total_runtime: 100,
          timeout: false
        )
      end

      it 'removes keys with nil values' do
        expect(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, { 'addr.b' => 'b' }, 1_000)
          .and_return([result.status, result])

        runner.run({ 'addr.a' => 'a', 'addr.aa' => nil }, { 'addr.b' => 'b', 'addr.bb' => nil }, 1_000)
      end

      it 'removes keys with empty strings' do
        expect(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, { 'addr.b' => 'b' }, 1_000)
          .and_return([result.status, result])

        runner.run({ 'addr.a' => 'a', 'addr.aa' => '' }, { 'addr.b' => 'b', 'addr.bb' => '' }, 1_000)
      end

      it 'removes keys with empty arrays' do
        expect(waf_context).to receive(:run)
          .with({ 'addr.a' => ['a'] }, { 'addr.b' => ['b'] }, 1_000)
          .and_return([result.status, result])

        runner.run({ 'addr.a' => ['a'], 'addr.aa' => [] }, { 'addr.b' => ['b'], 'addr.bb' => [] }, 1_000)
      end

      it 'removes keys with empty hashes' do
        expect(waf_context).to receive(:run)
          .with({ 'addr.a' => { 'a' => '1' } }, { 'addr.b' => { 'b' => '2' } }, 1_000)
          .and_return([result.status, result])

        runner.run({ 'addr.a' => { 'a' => '1' }, 'addr.aa' => {} }, { 'addr.b' => { 'b' => '2' }, 'addr.bb' => {} }, 1_000)
      end

      it 'does not remove keys with boolean values' do
        expect(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a', 'addr.aa' => true }, { 'addr.b' => 'b', 'addr.bb' => false }, 1_000)
          .and_return([result.status, result])

        runner.run({ 'addr.a' => 'a', 'addr.aa' => true }, { 'addr.b' => 'b', 'addr.bb' => false }, 1_000)
      end
    end

    context 'when run succeeded with a match result' do
      before do
        allow(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, {}, 1_000)
          .and_return([waf_result.status, waf_result])
      end

      let(:waf_result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :match,
          events: [],
          actions: {
            'block_request' => { 'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto' }
          },
          derivatives: {},
          timeout: false,
          total_runtime: 10
        )
      end
      let(:result) { runner.run({ 'addr.a' => 'a' }, {}, 1_000) }

      it 'returns match result with filled fields' do
        expect(result).to be_instance_of(Datadog::AppSec::SecurityEngine::Result::Match)
        expect(result).not_to be_timeout
        expect(result.events).to eq([])
        expect(result.actions).to eq(
          { 'block_request' => { 'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto' } }
        )
        expect(result.derivatives).to eq({})
        expect(result.duration_ns).to eq(10)
        expect(result.duration_ext_ns).to be > result.duration_ns
      end
    end

    context 'when run succeeded with an ok result' do
      before do
        allow(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, {}, 1_000)
          .and_return([waf_result.status, waf_result])
      end

      let(:waf_result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :ok,
          events: [],
          actions: {},
          derivatives: {},
          timeout: true,
          total_runtime: 100
        )
      end
      let(:result) { runner.run({ 'addr.a' => 'a' }, {}, 1_000) }

      it 'returns match result with filled fields' do
        expect(result).to be_instance_of(Datadog::AppSec::SecurityEngine::Result::Ok)
        expect(result).to be_timeout
        expect(result.events).to eq([])
        expect(result.actions).to eq({})
        expect(result.derivatives).to eq({})
        expect(result.duration_ns).to eq(100)
        expect(result.duration_ext_ns).to be > result.duration_ns
      end
    end

    context 'when run failed with libddwaf error result' do
      before do
        allow(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, {}, 1_000)
          .and_return([waf_result.status, waf_result])
      end

      let(:waf_result) do
        instance_double(Datadog::AppSec::WAF::Result, status: :err_invalid_object, timeout: false)
      end

      it 'sends telemetry error' do
        expect(telemetry).to receive(:error)
          .with(/libddwaf:[\d.]+ method:ddwaf_run execution error: :err_invalid_object/)

        runner.run({ 'addr.a' => 'a' }, {}, 1_000)
      end
    end

    context 'when run failed with libddwaf low-level exception' do
      before do
        allow(waf_context).to receive(:run)
          .with({ 'addr.a' => 'a' }, {}, 1_000)
          .and_raise(Datadog::AppSec::WAF::LibDDWAF::Error, 'Could not convert persistent data')
      end

      let(:run_result) { runner.run({ 'addr.a' => 'a' }, {}, 1_000) }

      it 'sends telemetry report' do
        expect(telemetry).to receive(:error)
          .with(/libddwaf:[\d.]+ method:ddwaf_run execution error: :err_internal/)

        expect(telemetry).to receive(:report)
          .with(kind_of(Datadog::AppSec::WAF::LibDDWAF::Error), description: 'libddwaf-rb internal low-level error')

        expect(run_result).to be_kind_of(Datadog::AppSec::SecurityEngine::Result::Error)
        expect(run_result.duration_ext_ns).to be > 0
      end
    end
  end
end
