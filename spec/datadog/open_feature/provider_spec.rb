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
      let(:flag_eval_evp_hook) { instance_double(Datadog::OpenFeature::Hooks::FlagEvalEVPHook) }

      before do
        allow(components).to receive(:open_feature).and_return(open_feature_component)
        allow(open_feature_component).to receive(:flag_eval_metrics_hook).and_return(flag_eval_metrics_hook)
        allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(flag_eval_evp_hook)
      end

      it 'returns OTel and EVP hooks so both observe SDK-final details' do
        expect(provider.hooks).to eq([flag_eval_metrics_hook, flag_eval_evp_hook])
      end

      context 'when EVP hook is disabled (killswitch)' do
        before { allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(nil) }

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

  describe 'SDK-final EVP hook dispatch' do
    let(:components) { instance_double(Datadog::Core::Configuration::Components) }
    let(:open_feature_component) { instance_double(Datadog::OpenFeature::Component) }
    let(:flag_eval_metrics_hook) do
      double('FlagEvalMetricsHook', before: nil, after: nil, error: nil, finally: nil)
    end
    let(:flag_eval_evp_hook) do
      double('FlagEvalEVPHook', before: nil, after: nil, error: nil, finally: nil)
    end
    let(:evaluation_context) do
      ::OpenFeature::SDK::EvaluationContext.new(targeting_key: 'user-1', env: 'prod')
    end
    let(:client) { ::OpenFeature::SDK::Client.new(provider: provider) }

    before do
      allow(Datadog).to receive(:send).with(:components).and_return(components)
      allow(components).to receive(:open_feature).and_return(open_feature_component)
      allow(open_feature_component).to receive(:flag_eval_metrics_hook).and_return(flag_eval_metrics_hook)
      allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(flag_eval_evp_hook)
    end

    it 'passes provider success details to the EVP hook after SDK finalization' do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 'variant-a', reason: 'TARGETING_MATCH', variant: 'variant-a',
        flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
      )
      allow(engine).to receive(:fetch_value).and_return(result)

      details = client.fetch_string_details(
        flag_key: 'my-flag', default_value: 'default', evaluation_context: evaluation_context
      )

      expect(details.value).to eq('variant-a')
      expect(flag_eval_evp_hook).to have_received(:finally) do |hook_context:, evaluation_details:, **|
        expect(hook_context.flag_key).to eq('my-flag')
        expect(hook_context.evaluation_context.targeting_key).to eq('user-1')
        expect(evaluation_details.variant).to eq('variant-a')
        expect(evaluation_details.error_message).to be_nil
        expect(evaluation_details.flag_metadata).to include('dd.eval.timestamp_ms')
      end
    end

    it 'passes SDK-final type mismatch details to the EVP hook' do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 123, reason: 'TARGETING_MATCH', variant: 'variant-a',
        flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
      )
      allow(engine).to receive(:fetch_value).and_return(result)

      details = client.fetch_string_details(
        flag_key: 'type-mismatch-flag', default_value: 'default', evaluation_context: evaluation_context
      )

      expect(details.value).to eq('default')
      expect(details.error_code).to eq('TYPE_MISMATCH')
      expect(details.reason).to eq('ERROR')
      expect(flag_eval_evp_hook).to have_received(:finally) do |evaluation_details:, **|
        expect(evaluation_details.value).to eq('default')
        expect(evaluation_details.error_code).to eq('TYPE_MISMATCH')
        expect(evaluation_details.reason).to eq('ERROR')
        expect(evaluation_details.flag_metadata).to include('dd.eval.timestamp_ms')
      end
    end

    it 'passes SDK-final after-hook failure details to the EVP hook' do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 'variant-a', reason: 'TARGETING_MATCH', variant: 'variant-a',
        flag_metadata: {}, allocation_key: nil, extra_logging: {}, log?: false, error?: false
      )
      failing_after_hook = double('FailingAfterHook', before: nil, error: nil, finally: nil)
      allow(failing_after_hook).to receive(:after).and_raise(RuntimeError, 'after boom')
      allow(engine).to receive(:fetch_value).and_return(result)

      details = client.fetch_string_details(
        flag_key: 'after-hook-flag',
        default_value: 'default',
        evaluation_context: evaluation_context,
        hooks: [failing_after_hook]
      )

      expect(details.value).to eq('default')
      expect(details.reason).to eq('ERROR')
      expect(details.error_message).to eq('after boom')
      expect(flag_eval_evp_hook).to have_received(:finally) do |hook_context:, evaluation_details:, **|
        expect(hook_context.flag_key).to eq('after-hook-flag')
        expect(evaluation_details.value).to eq('default')
        expect(evaluation_details.variant).to be_nil
        expect(evaluation_details.reason).to eq('ERROR')
        expect(evaluation_details.error_message).to eq('after boom')
      end
    end

    it 'passes provider error details to the EVP hook' do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 'default', reason: 'ERROR', variant: nil, error_code: 'FLAG_NOT_FOUND',
        error_message: 'nope', flag_metadata: {}, allocation_key: nil, extra_logging: {},
        log?: false, error?: true
      )
      allow(engine).to receive(:fetch_value).and_return(result)

      details = client.fetch_string_details(flag_key: 'err-flag', default_value: 'default')

      expect(details.value).to eq('default')
      expect(details.error_message).to eq('nope')
      expect(flag_eval_evp_hook).to have_received(:finally) do |evaluation_details:, **|
        expect(evaluation_details.variant).to be_nil
        expect(evaluation_details.error_message).to eq('nope')
        expect(evaluation_details.flag_metadata).to include('dd.eval.timestamp_ms')
      end
    end

    context 'with a real EVP hook and Writer' do
      let(:writer) { Datadog::OpenFeature::FlagEvaluation::Writer.new(transport: evp_transport, logger: logger) }
      let(:evp_transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
      let(:real_flag_eval_evp_hook) { Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(writer) }

      before do
        # No bare sleep in shutdown synchronization: stub the background thread, drive flush manually.
        allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
          .to receive(:start_background_thread).and_return(nil)
        allow(open_feature_component).to receive(:flag_eval_metrics_hook).and_return(nil)
        allow(open_feature_component).to receive(:flag_eval_evp_hook).and_return(real_flag_eval_evp_hook)
        allow(logger).to receive(:debug)
      end

      it 'enqueues an event into the Writer when the SDK client evaluates successfully' do
        result = Datadog::OpenFeature::ResolutionDetails.new(
          value: 'variant-a', reason: 'TARGETING_MATCH', variant: 'variant-a',
          flag_metadata: {}, allocation_key: 'alloc-9', extra_logging: {}, log?: false, error?: false
        )
        allow(engine).to receive(:fetch_value).and_return(result)

        client.fetch_string_value(
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
          expect(row['targeting_key']).to eq('user-1')
          expect(row['context']).to eq('evaluation' => {'env' => 'prod'})
        end
      ensure
        writer.stop
      end
    end
  end

  # Provider stamps 'dd.eval.timestamp_ms' into flag metadata at eval entry, which the
  # EVP hook reads for first/last_evaluation.
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

    it "exposes the stamped timestamp on provider error metadata" do
      result = Datadog::OpenFeature::ResolutionDetails.new(
        value: 'd', reason: 'ERROR', variant: nil, error_code: 'FLAG_NOT_FOUND',
        error_message: 'missing', flag_metadata: {}, allocation_key: nil, extra_logging: {},
        log?: false, error?: true
      )
      allow(engine).to receive(:fetch_value).and_return(result)

      res = provider.fetch_string_value(flag_key: 'ts-err', default_value: 'd')

      expect(res.flag_metadata['dd.eval.timestamp_ms']).to eq(1_700_000_000_000)
      expect(res.error_message).to eq('missing')
    end
  end
end
