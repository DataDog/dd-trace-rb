# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/provider'
require 'datadog/open_feature/evaluation_engine'
require 'datadog/open_feature/hooks/flag_eval_metrics_hook'
require 'datadog/open_feature/hooks/flag_eval_evp_hook'
require 'datadog/open_feature/flagevaluation/writer'

RSpec.describe Datadog::OpenFeature::Provider do
  before do
    allow(telemetry).to receive(:report)
    allow(reporter).to receive(:report)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    # call_evp_hook drives the EVP hook directly (Ruby openfeature-sdk does not invoke provider
    # hooks during evaluation). Stub it as a no-op for tests not specifically testing EVP emission.
    allow(provider).to receive(:call_evp_hook)
  end

  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger) }

  subject(:provider) { described_class.new }

  describe '#fetch_boolean_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_boolean_value(flag_key: 'flag', default_value: false)

        expect(result.value).to eq(false)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_string_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_string_value(flag_key: 'flag', default_value: 'default')

        expect(result.value).to eq('default')
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_number_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_number_value(flag_key: 'flag', default_value: 0)

        expect(result.value).to eq(0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_integer_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_integer_value(flag_key: 'flag', default_value: 1)

        expect(result.value).to eq(1)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_float_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_float_value(flag_key: 'flag', default_value: 0.0)

        expect(result.value).to eq(0.0)
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end
  end

  describe '#fetch_object_value' do
    context 'when engine is not configured' do
      before { allow(Datadog::OpenFeature).to receive(:engine).and_return(nil) }

      it 'returns default value with error details' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: {'default' => true})

        expect(result.value).to eq({'default' => true})
        expect(result.error_message).to match(/OpenFeature component must be configured/)
      end
    end

    context 'when value is a JSON string' do
      before do
        allow(engine).to receive(:fetch_value).and_return(details)
        allow(details).to receive(:value).and_raise(Datadog::Core::FeatureFlags::Error, 'Ooops')
      end

      let(:details) do
        Datadog::OpenFeature::ResolutionDetails.new(
          value: '{}', reason: 'MATCH', variant: 'blue', flag_metadata: {},
          allocation_key: 'joe', extra_logging: {}, log?: true, error?: false
        )
      end

      it 'returns error and fallback to the default value' do
        result = provider.fetch_object_value(flag_key: 'flag', default_value: {'default' => true})

        expect(result.value).to eq('default' => true)
        expect(result.reason).to eq('ERROR')
      end
    end
  end

  describe '#hooks' do
    let(:components) { instance_double(Datadog::Core::Configuration::Components) }
    let(:open_feature_component) { instance_double(Datadog::OpenFeature::Component) }

    before do
      allow(Datadog).to receive(:send).with(:components).and_return(components)
    end

    context 'when OpenFeature component is configured' do
      let(:flag_eval_metrics_hook) { instance_double(Datadog::OpenFeature::Hooks::FlagEvalMetricsHook) }
      before do
        allow(components).to receive(:open_feature).and_return(open_feature_component)
        allow(open_feature_component).to receive(:flag_eval_metrics_hook).and_return(flag_eval_metrics_hook)
      end

      it 'returns only the OTel flag eval hook to avoid EVP lifecycle double-counting' do
        expect(open_feature_component).not_to receive(:flag_eval_evp_hook)
        expect(provider.hooks).to eq([flag_eval_metrics_hook])
      end

      context 'when EVP hook is disabled (killswitch)' do
        it 'returns array with only the OTel flag eval hook' do
          expect(provider.hooks).to eq([flag_eval_metrics_hook])
        end
      end
    end

    context 'when OpenFeature component is not configured' do
      before do
        allow(components).to receive(:open_feature).and_return(nil)
      end

      it 'returns empty array' do
        expect(provider.hooks).to eq([])
      end
    end
  end

  describe '#call_evp_hook (EVP direct dispatch)' do
    # Ruby openfeature-sdk (through at least 0.5.x) does not invoke provider hooks during
    # evaluation. call_evp_hook is called directly from #evaluate to ensure EVP events are
    # emitted on every evaluation.

    let(:components) { instance_double(Datadog::Core::Configuration::Components) }
    let(:open_feature_component) { instance_double(Datadog::OpenFeature::Component) }
    let(:evp_hook) { instance_double(Datadog::OpenFeature::Hooks::FlagEvalEVPHook) }
    let(:evaluation_context) do
      ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'user-1', env: 'prod')
    end

    before do
      allow(Datadog).to receive(:send).with(:components).and_return(components)
      allow(components).to receive(:open_feature).and_return(open_feature_component)
      allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(evp_hook)
      allow(evp_hook).to receive(:finally)
    end

    it 'is called during fetch_string_value evaluation' do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 'variant-a', reason: 'TARGETING_MATCH', variant: 'variant-a',
        flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
      )
      allow(engine).to receive(:fetch_value).and_return(result)
      # Unset the global no-op stub for this context so we test the real method
      allow(provider).to receive(:call_evp_hook).and_call_original

      provider.fetch_string_value(
        flag_key: 'my-flag', default_value: 'default', evaluation_context: evaluation_context
      )

      expect(evp_hook).to have_received(:finally) do |hook_context:, evaluation_details:, **|
        expect(hook_context.flag_key).to eq('my-flag')
        expect(hook_context.evaluation_context.targeting_key).to eq('user-1')
        expect(hook_context.evaluation_context.attributes).to eq('env' => 'prod')
        expect(evaluation_details.variant).to eq('variant-a')
        expect(evaluation_details.error_message).to be_nil
      end
    end

    context 'when EVP hook is nil (killswitch off)' do
      before do
        allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(nil)
      end

      it 'does not raise and returns the evaluation result' do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'default', reason: 'ERROR', variant: nil,
          flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: true,
          error_code: 'FLAG_NOT_FOUND', error_message: 'not found'
        )
        allow(engine).to receive(:fetch_value).and_return(result)
        allow(provider).to receive(:call_evp_hook).and_call_original

        res = provider.fetch_string_value(flag_key: 'x', default_value: 'default')
        expect(res.value).to eq('default')
      end
    end

    context 'when component is absent' do
      before do
        allow(components).to receive(:open_feature).and_return(nil)
      end

      it 'does not raise' do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'v', reason: 'STATIC', variant: 'v',
          flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
        )
        allow(engine).to receive(:fetch_value).and_return(result)
        allow(provider).to receive(:call_evp_hook).and_call_original

        expect { provider.fetch_string_value(flag_key: 'y', default_value: 'v') }.not_to raise_error
      end
    end

    # The EVP hook fires on the SDK's real evaluation entrypoint, which is the provider's
    # #evaluate (the Ruby openfeature-sdk does not auto-run provider hooks). Proven against a
    # real Writer (no stub of the hook): enqueue must actually happen on a successful eval.
    context 'fires on the real evaluation path (drives a real Writer)' do
      let(:writer) { Datadog::OpenFeature::FlagEvaluation::Writer.new(transport: evp_transport, logger: logger) }
      let(:evp_transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
      let(:real_evp_hook) { Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(writer) }

      before do
        # No bare sleep in shutdown synchronization: stub the background thread, drive flush manually.
        allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
          .to receive(:start_background_thread).and_return(nil)
        allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(real_evp_hook)
        allow(logger).to receive(:debug)
      end

      it 'enqueues an event into the Writer when fetch_string_value succeeds' do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'variant-a', reason: 'TARGETING_MATCH', variant: 'variant-a',
          flag_metadata: {}, allocation_key: 'alloc-9', extra_logging: {}, log?: false, error?: false
        )
        allow(engine).to receive(:fetch_value).and_return(result)
        allow(provider).to receive(:call_evp_hook).and_call_original

        provider.fetch_string_value(
          flag_key: 'real-flag', default_value: 'default', evaluation_context: evaluation_context
        )

        # Drive the writer's drain manually (background thread stubbed) and assert the transport
        # received the real flagevaluation built from the enqueued event.
        writer.send(:drain_and_flush)
        expect(evp_transport).to have_received(:send_flag_evaluations) do |payload|
          row = payload['flagEvaluations'].first
          expect(row['flag']['key']).to eq('real-flag')
          expect(row['variant']).to eq('key' => 'variant-a')
          expect(row['allocation']).to eq('key' => 'alloc-9')
        end
      ensure
        writer.stop
      end
    end

    # ALL evaluation exit paths must reach (or safely bypass) the EVP hook.
    context 'evaluation exit paths' do
      before do
        allow(provider).to receive(:call_evp_hook).and_call_original
        allow(evp_hook).to receive(:finally)
      end

      it 'engine error path: drives the EVP hook with error_message + nil variant' do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'default', reason: 'ERROR', variant: nil, error_code: 'FLAG_NOT_FOUND',
          error_message: 'nope', flag_metadata: {}, allocation_key: nil, extra_logging: {},
          log?: false, error?: true
        )
        allow(engine).to receive(:fetch_value).and_return(result)

        res = provider.fetch_string_value(flag_key: 'err-flag', default_value: 'default')

        expect(res.value).to eq('default')
        expect(evp_hook).to have_received(:finally) do |evaluation_details:, **|
          expect(evaluation_details.variant).to be_nil
          expect(evaluation_details.error_message).to eq('nope')
        end
      end

      it 'no-engine early return: does NOT drive the EVP hook (scoped out — no eval occurred)' do
        allow(Datadog::OpenFeature).to receive(:engine).and_return(nil)

        res = provider.fetch_string_value(flag_key: 'no-engine', default_value: 'd')

        expect(res.error_message).to match(/must be configured/)
        expect(evp_hook).not_to have_received(:finally)
      end

      it 'rescued provider exception: drives the EVP hook with error_message + nil variant' do
        allow(engine).to receive(:fetch_value).and_raise(RuntimeError, 'boom')

        res = nil
        expect { res = provider.fetch_string_value(flag_key: 'boom-flag', default_value: 'd') }
          .not_to raise_error
        expect(res.value).to eq('d')
        expect(res.reason).to eq('ERROR')
        expect(evp_hook).to have_received(:finally) do |hook_context:, evaluation_details:, **|
          expect(hook_context.flag_key).to eq('boom-flag')
          expect(evaluation_details.variant).to be_nil
          expect(evaluation_details.error_message).to eq('RuntimeError: boom')
          expect(evaluation_details.flag_metadata).to include('dd.eval.timestamp_ms')
        end
      end
    end

    # Provider stamps 'dd.eval.timestamp_ms' into flag metadata at eval entry, which the
    # EVP hook reads for first/last_evaluation. Proven by inspecting the metadata the hook sees.
    context 'eval-time metadata stamping' do
      # Override the configurable time provider (no Timecop dependency). The provider lambda runs
      # with self == Datadog::Core::Utils::Time, so capture the frozen value in a local closure.
      around do |example|
        frozen = Time.at(1_700_000_000)
        Datadog::Core::Utils::Time.now_provider = -> { frozen }
        example.run
      ensure
        Datadog::Core::Utils::Time.now_provider = -> { Time.now }
      end

      it "stamps dd.eval.timestamp_ms into the metadata the EVP hook receives" do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'v', reason: 'STATIC', variant: 'v',
          flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
        )
        allow(engine).to receive(:fetch_value).and_return(result)
        allow(provider).to receive(:call_evp_hook).and_call_original
        allow(evp_hook).to receive(:finally)

        provider.fetch_string_value(flag_key: 'ts-flag', default_value: 'd')

        expect(evp_hook).to have_received(:finally) do |evaluation_details:, **|
          expect(evaluation_details.flag_metadata['dd.eval.timestamp_ms']).to eq(1_700_000_000_000)
        end
      end

      it "exposes the stamped timestamp on the success-path ResolutionDetails metadata" do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'v', reason: 'STATIC', variant: 'v',
          flag_metadata: {'existing' => 'kept'}, allocation_key: nil, extra_logging: {},
          log?: false, error?: false
        )
        allow(engine).to receive(:fetch_value).and_return(result)

        res = provider.fetch_string_value(flag_key: 'ts-flag2', default_value: 'd')

        expect(res.flag_metadata['dd.eval.timestamp_ms']).to eq(1_700_000_000_000)
        expect(res.flag_metadata['existing']).to eq('kept')
      end
    end
  end
end
