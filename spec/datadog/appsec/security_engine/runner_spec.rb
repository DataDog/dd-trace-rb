# frozen_string_literal: true

require 'libddwaf'

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor/rule_loader'

RSpec.describe Datadog::AppSec::SecurityEngine::Runner do
  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(thread_safe_ref).to receive(:acquire).and_return(waf_handle)
    allow(waf_handle).to receive(:build_context).and_return(waf_context)
  end

  let(:thread_safe_ref) { instance_double(Datadog::AppSec::ThreadSafeRef) }
  let(:waf_handle) { instance_double(Datadog::AppSec::WAF::Handle) }
  let(:waf_context) { instance_double(Datadog::AppSec::WAF::Context) }
  let(:telemetry) { spy(Datadog::Core::Telemetry::Component) }

  subject(:runner) { described_class.new(thread_safe_ref, ruleset_version: '1.0.0') }

  describe '#run' do
    context 'when keys contain values to clean' do
      let(:result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :ok,
          events: [],
          actions: {},
          attributes: {},
          duration: 100,
          keep?: false,
          timeout?: false,
          input_truncated?: false
        )
      end

      it 'removes keys with nil values' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {'addr.b' => 'b'}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => 'a', 'addr.aa' => nil}, {'addr.b' => 'b', 'addr.bb' => nil}, 1_000)
      end

      it 'removes keys with empty strings' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {'addr.b' => 'b'}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => 'a', 'addr.aa' => ''}, {'addr.b' => 'b', 'addr.bb' => ''}, 1_000)
      end

      it 'removes keys with empty arrays' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => ['a']}, {'addr.b' => ['b']}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => ['a'], 'addr.aa' => []}, {'addr.b' => ['b'], 'addr.bb' => []}, 1_000)
      end

      it 'removes keys with empty hashes' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => {'a' => '1'}}, {'addr.b' => {'b' => '2'}}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => {'a' => '1'}, 'addr.aa' => {}}, {'addr.b' => {'b' => '2'}, 'addr.bb' => {}}, 1_000)
      end

      it 'does not remove keys with boolean values' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => 'a', 'addr.aa' => true}, {'addr.b' => 'b', 'addr.bb' => false}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => 'a', 'addr.aa' => true}, {'addr.b' => 'b', 'addr.bb' => false}, 1_000)
      end

      it 'does not remove keys with integer values' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => 42}, {'addr.b' => 100}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => 42}, {'addr.b' => 100}, 1_000)
      end

      it 'does not remove keys with float values' do
        expect(waf_context).to receive(:run)
          .with({'addr.a' => 3.14}, {'addr.b' => 2.71}, 1_000)
          .and_return(result)

        runner.run({'addr.a' => 3.14}, {'addr.b' => 2.71}, 1_000)
      end
    end

    context 'when run succeeded with a match result' do
      before do
        allow(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {}, 1_000)
          .and_return(waf_result)
      end

      let(:waf_result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :match,
          events: [],
          actions: {
            'block_request' => {'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto'}
          },
          attributes: {},
          duration: 10,
          keep?: false,
          timeout?: false,
          input_truncated?: false
        )
      end
      let(:result) { runner.run({'addr.a' => 'a'}, {}, 1_000) }

      it 'returns match result with filled fields' do
        expect(result).to be_instance_of(Datadog::AppSec::SecurityEngine::Result::Match)
        expect(result).not_to be_keep
        expect(result).not_to be_timeout
        expect(result).not_to be_input_truncated
        expect(result.events).to eq([])
        expect(result.actions).to eq(
          {'block_request' => {'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto'}}
        )
        expect(result.attributes).to eq({})
        expect(result.duration_ns).to eq(10)
        expect(result.duration_ext_ns).to be > result.duration_ns
      end

      context 'when WAF::Result#input_truncated? is true' do
        let(:waf_result) do
          instance_double(
            Datadog::AppSec::WAF::Result,
            status: :match,
            events: [],
            actions: {
              'block_request' => {'grpc_status_code' => '10', 'status_code' => '403', 'type' => 'auto'}
            },
            attributes: {},
            duration: 10,
            keep?: false,
            timeout?: false,
            input_truncated?: true
          )
        end

        it 'returns result with input_trucnated set to true' do
          expect(result).to be_input_truncated
        end
      end
    end

    context 'when run succeeded with an ok result' do
      before do
        allow(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {}, 1_000)
          .and_return(waf_result)
      end

      let(:waf_result) do
        instance_double(
          Datadog::AppSec::WAF::Result,
          status: :ok,
          events: [],
          actions: {},
          attributes: {},
          duration: 100,
          keep?: true,
          timeout?: true,
          input_truncated?: false
        )
      end
      let(:result) { runner.run({'addr.a' => 'a'}, {}, 1_000) }

      it 'returns match result with filled fields' do
        expect(result).to be_instance_of(Datadog::AppSec::SecurityEngine::Result::Ok)
        expect(result).to be_keep
        expect(result).to be_timeout
        expect(result).not_to be_input_truncated
        expect(result.events).to eq([])
        expect(result.actions).to eq({})
        expect(result.attributes).to eq({})
        expect(result.duration_ns).to eq(100)
        expect(result.duration_ext_ns).to be > result.duration_ns
      end

      context 'when WAF::Result#input_truncated? is true' do
        let(:waf_result) do
          instance_double(
            Datadog::AppSec::WAF::Result, status: :ok, events: [], actions: {}, attributes: {},
            duration: 10, timeout?: false, keep?: false, input_truncated?: true
          )
        end

        it 'returns result with input_trucnated set to true' do
          expect(result).to be_input_truncated
        end
      end
    end

    context 'when run failed with libddwaf error result' do
      before do
        allow(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {}, 1_000)
          .and_return(waf_result)
      end

      let(:waf_result) do
        instance_double(
          Datadog::AppSec::WAF::Result, status: :err_invalid_object, timeout?: false, input_truncated?: false
        )
      end

      it 'sends telemetry error' do
        expect(Datadog::AppSec.telemetry).to receive(:error)
          .with(/libddwaf:[\d.]+ method:ddwaf_run execution error: :err_invalid_object/)

        runner.run({'addr.a' => 'a'}, {}, 1_000)
      end

      context 'when WAF::Result#input_truncated? is true' do
        let(:waf_result) do
          instance_double(
            Datadog::AppSec::WAF::Result, status: :err_invalid_object, timeout?: true, input_truncated?: true
          )
        end

        it 'returns result with input_trucnated set to true' do
          expect(waf_result).to be_input_truncated
        end
      end
    end

    context 'when run failed with libddwaf low-level exception' do
      before do
        allow(waf_context).to receive(:run)
          .with({'addr.a' => 'a'}, {}, 1_000)
          .and_raise(Datadog::AppSec::WAF::LibDDWAFError, 'Could not convert persistent data')
      end

      let(:run_result) { runner.run({'addr.a' => 'a'}, {}, 1_000) }

      it 'sends telemetry report' do
        expect(Datadog::AppSec.telemetry).to receive(:error)
          .with(/libddwaf:[\d.]+ method:ddwaf_run execution error: :err_internal/)

        expect(Datadog::AppSec.telemetry).to receive(:report)
          .with(kind_of(Datadog::AppSec::WAF::LibDDWAFError), description: 'libddwaf-rb internal low-level error')

        expect(run_result).to be_kind_of(Datadog::AppSec::SecurityEngine::Result::Error)
        expect(run_result).not_to be_input_truncated
        expect(run_result.duration_ext_ns).to be > 0
      end
    end
  end

  describe '#finalize!' do
    it 'releases the waf handle when an error occurs' do
      # waf_context is lazily initialized, so we need to ensure it is called
      runner.waf_context

      allow(waf_context).to receive(:finalize!).and_raise(StandardError)
      expect(thread_safe_ref).to receive(:release).with(waf_handle)

      expect { runner.finalize! }.to raise_error(StandardError)
    end
  end
end
