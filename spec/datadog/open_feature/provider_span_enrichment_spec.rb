# frozen_string_literal: true

require 'spec_helper'

# End-to-end span-enrichment coverage that drives the REAL OpenFeature client
# path: `OpenFeature::SDK.build_client` -> `Datadog::OpenFeature::Provider#fetch_*`
# -> enrichment dispatch -> `ffe_*` tags on the local root APM span.
#
# This exercises the highest-risk behavior the unit specs cannot: that real Ruby
# evaluations actually trigger enrichment. Enrichment is driven directly from the
# provider's evaluation path (`Provider#enrich_span`), which works on every
# supported OpenFeature SDK version regardless of whether the SDK dispatches
# provider hooks. Only the native evaluation (`EvaluationEngine`) and the
# active-trace seam are stubbed — everything from the OpenFeature client through
# the provider down to the root-span write is the production code path. No native
# ext / libdatadog / Docker required.
require 'open_feature/sdk'
require 'datadog/open_feature'
require 'datadog/open_feature/provider'
require 'datadog/open_feature/evaluation_engine'
require 'datadog/open_feature/hooks/span_enrichment_hook'

RSpec.describe 'OpenFeature provider span enrichment (end-to-end)' do
  subject(:provider) { Datadog::OpenFeature::Provider.new }

  let(:engine) { instance_double(Datadog::OpenFeature::EvaluationEngine) }
  let(:span_enrichment_hook) do
    Datadog::OpenFeature::Hooks::SpanEnrichmentHook.new(
      Datadog::OpenFeature::Hooks::SpanEnrichmentHook::SpanEnrichmentStateStore.new,
      logger: instance_double(Datadog::Core::Logger, debug: nil)
    )
  end
  let(:open_feature_component) do
    instance_double(
      Datadog::OpenFeature::Component,
      engine: engine,
      # Newer OpenFeature SDKs (>= 0.6) dispatch provider hooks during
      # `Client#fetch_details`, which calls `Provider#hooks` -> the eval hooks.
      # Stub them (nil -> compacted out) so the verifying double accepts the call
      # on every supported SDK version.
      flag_eval_metrics_hook: nil,
      flag_eval_evp_hook: nil,
      span_enrichment_hook: span_enrichment_hook
    )
  end

  # The local root span is resolved off the active trace at capture time. Drive a
  # real TraceOperation and stub the global accessor to it (same seam the unit
  # spec uses), so `Provider#enrich_span` lands tags on this trace's root span.
  let(:trace_op) { Datadog::Tracing::TraceOperation.new }

  before do
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace_op)

    # Resolve the engine and (when the gate is on) the span-enrichment hook
    # through the real provider lookup path.
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    components = instance_double(Datadog::Core::Configuration::Components, open_feature: open_feature_component)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components).and_return(components)

    install_provider(provider)
  end

  after do
    # The OpenFeature API is a process-global singleton; reset it so providers
    # do not leak between examples.
    OpenFeature::SDK::API.instance.instance_variable_set(:@configuration, nil)
  end

  # Builds a Datadog ResolutionDetails (the engine's return shape). A nil
  # `serial_id` + nil `variant` models a runtime default; a present `serial_id`
  # models an assigned split.
  def resolution(value:, variant:, serial_id:, log: false)
    Datadog::OpenFeature::ResolutionDetails.new(
      value: value,
      reason: 'MATCH',
      variant: variant,
      flag_metadata: {},
      allocation_key: 'alloc',
      serial_id: serial_id,
      extra_logging: {},
      log?: log,
      error?: false
    )
  end

  def client(targeting_key: nil)
    context = OpenFeature::SDK::EvaluationContext.new(targeting_key: targeting_key) if targeting_key
    OpenFeature::SDK.build_client(evaluation_context: context)
  end

  # OpenFeature SDK >= 0.6 sets the provider asynchronously (spawns a background
  # init thread); use the synchronous variant when available so the test does not
  # leak that thread. Older SDKs (< 0.6) set the provider synchronously already.
  def install_provider(provider)
    if OpenFeature::SDK.respond_to?(:set_provider_and_wait)
      OpenFeature::SDK.set_provider_and_wait(provider)
    else
      OpenFeature::SDK.set_provider(provider)
    end
  end

  context 'when the gate is ON' do
    it 'attaches ffe_flags_enc to the root span after a real string evaluation' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'on', variant: 'enabled', serial_id: 100))

      trace_op.measure('root') do
        result = client.fetch_string_value(flag_key: 'flag-a', default_value: 'off')
        expect(result).to eq('on') # proves we went through the real provider path
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to eq('ZA==') # delta-varint([100]) -> base64
    end

    it 'emits ffe_subjects_enc only when do_log is authorized and a targeting key is present' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'on', variant: 'enabled', serial_id: 100, log: true))

      trace_op.measure('root') do
        client(targeting_key: 'user-123').fetch_string_value(flag_key: 'flag-a', default_value: 'off')
      end

      subjects = JSON.parse(trace_op.get_tag('ffe_subjects_enc'))
      expect(subjects.keys).to eq([Digest::SHA256.hexdigest('user-123')])
      expect(subjects[Digest::SHA256.hexdigest('user-123')]).to eq('ZA==')
    end

    it 'does not emit ffe_subjects_enc when do_log is false' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'on', variant: 'enabled', serial_id: 100, log: false))

      trace_op.measure('root') do
        client(targeting_key: 'user-123').fetch_string_value(flag_key: 'flag-a', default_value: 'off')
      end

      expect(trace_op.get_tag('ffe_subjects_enc')).to be_nil
    end

    it 'captures a runtime default (missing variant) into ffe_runtime_defaults' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'control', variant: nil, serial_id: nil))

      trace_op.measure('root') do
        client.fetch_string_value(flag_key: 'flag-default', default_value: 'control')
      end

      defaults = JSON.parse(trace_op.get_tag('ffe_runtime_defaults'))
      expect(defaults).to eq('flag-default' => 'control')
    end

    it 'aggregates evaluations from a child span onto the one local root' do
      allow(engine).to receive(:fetch_value).and_return(
        resolution(value: 'on', variant: 'enabled', serial_id: 100),
        resolution(value: 'on', variant: 'enabled', serial_id: 108)
      )

      ofc = client
      child_op = nil
      trace_op.measure('root') do
        ofc.fetch_string_value(flag_key: 'flag-a', default_value: 'off')
        trace_op.measure('child') do |span_op, _t|
          child_op = span_op
          # Child-span evaluation must still land on the local root.
          ofc.fetch_string_value(flag_key: 'flag-b', default_value: 'off')
        end
      end

      # Both serial ids aggregate onto the root; the child carries no ffe_* tags.
      expect(trace_op.get_tag('ffe_flags_enc'))
        .to eq(Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec.encode_delta_varint(Set[100, 108]))
      expect(child_op.get_tag('ffe_flags_enc')).to be_nil
    end

    it 'does not lose serial ids under concurrent evaluations on the same root' do
      serial_ids = (1..50).to_a
      queue = Queue.new
      serial_ids.each { |id| queue << id }
      allow(engine).to receive(:fetch_value) do
        id = queue.pop(true)
        resolution(value: 'on', variant: 'enabled', serial_id: id)
      end

      ofc = client
      trace_op.measure('root') do
        # All worker threads see the same active trace (the stub returns trace_op
        # regardless of thread), modelling concurrent child-span evaluations.
        threads = serial_ids.map do
          Thread.new { ofc.fetch_string_value(flag_key: 'flag', default_value: 'off') }
        end
        threads.each(&:join)
      end

      encoded = trace_op.get_tag('ffe_flags_enc')
      decoded = encoded.unpack1('m0').bytes
      # Every terminating byte (MSB clear) is one serial id; all 50 must survive
      # the concurrent capture (the hook's Mutex guards the compound mutations).
      count = decoded.count { |b| (b & 0x80).zero? }
      expect(count).to eq(serial_ids.size)
    end

    it 'still works after provider reconfiguration (re-set_provider)' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'on', variant: 'enabled', serial_id: 100))

      # Reconfigure with a fresh provider instance reusing the same component/hook.
      install_provider(Datadog::OpenFeature::Provider.new)

      trace_op.measure('root') do
        OpenFeature::SDK.build_client.fetch_string_value(flag_key: 'flag-a', default_value: 'off')
      end

      # Set-deduped value is written exactly once with the correct encoding.
      expect(trace_op.get_tag('ffe_flags_enc')).to eq('ZA==')
    end
  end

  context 'when the gate is OFF (no hook constructed)' do
    let(:open_feature_component) do
      instance_double(
        Datadog::OpenFeature::Component,
        engine: engine,
        flag_eval_metrics_hook: nil,
        flag_eval_evp_hook: nil,
        span_enrichment_hook: nil
      )
    end

    it 'writes no ffe_* tags and stays fully inert' do
      allow(engine).to receive(:fetch_value)
        .and_return(resolution(value: 'on', variant: 'enabled', serial_id: 100, log: true))

      trace_op.measure('root') do
        client(targeting_key: 'user-123').fetch_string_value(flag_key: 'flag-a', default_value: 'off')
      end

      expect(trace_op.get_tag('ffe_flags_enc')).to be_nil
      expect(trace_op.get_tag('ffe_subjects_enc')).to be_nil
      expect(trace_op.get_tag('ffe_runtime_defaults')).to be_nil
    end
  end
end
