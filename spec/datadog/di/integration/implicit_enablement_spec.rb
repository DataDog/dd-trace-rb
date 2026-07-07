require 'spec_helper'
require 'datadog/di/spec_helper'
require 'datadog/di'
require 'datadog/tracing/remote'

# Target class for the method probe used below. Loaded before the RC
# enable signal arrives — this is the canonical "code loaded before
# enablement" case that always-build + late activation is meant to fix.
class ImplicitEnablementSpecTargetClass
  def target_method
    42
  end
end

RSpec.describe 'DI implicit enablement integration' do
  di_test
  deactivate_code_tracking

  # Exercises the full APM_TRACING → DI::Remote.handle_rc_enablement →
  # component.start! chain in-process, then drops a LIVE_DEBUGGING probe
  # and verifies the in-stopped-state component refuses probes, the
  # started component accepts and fires them, and the subsequent
  # enabled=false stops the component and unhooks installed probes.

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.remote.enabled = true
      # Note: dynamic_instrumentation.enabled stays at its default (false).
      # This is the implicit-enablement scenario — the customer never set
      # the env var; DI must come up via RC.
      s.dynamic_instrumentation.internal.development = true
      s.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:agent_settings) { instance_double_agent_settings_with_stubs }
  let(:logger) { instance_double(Logger) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger, telemetry: telemetry)
  end

  let(:symbol_database) do
    # Tracing::Remote.process_config replays (resume_pending_upload) or stops
    # (stop_for_di_disable) Symbol Database when a dynamic_instrumentation_enabled
    # signal arrives. This test builds only a DI component, so expose a Symbol
    # Database stand-in that accepts the two lifecycle calls. The upload behavior
    # itself is verified in spec/datadog/tracing/remote_spec.rb.
    instance_double(
      Datadog::SymbolDatabase::Component,
      resume_pending_upload: nil,
      stop_for_di_disable: nil,
    )
  end

  let(:components) do
    # Stand-in for Core::Configuration::Components. handle_rc_enablement
    # reaches the component via Datadog.send(:components).dynamic_instrumentation
    # and Tracing::Remote.process_config calls reconfigure_sampler on it for
    # each tracing dynamic-option update. We expose only what's needed.
    instance_double(
      Datadog::Core::Configuration::Components,
      dynamic_instrumentation: component,
      telemetry: telemetry,
      symbol_database: symbol_database,
    )
  end

  # The probe notifier worker thread runs in the background and posts probe
  # status events over HTTP. In tests we replace its transports with doubles
  # so probe installation does not attempt real network calls.
  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport).tap do |t|
      allow(t).to receive(:send_diagnostics)
    end
  end

  let(:input_transport) do
    instance_double(Datadog::DI::Transport::Input::Transport).tap do |t|
      allow(t).to receive(:send_input)
    end
  end

  before do
    allow(logger).to receive(:debug)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components).and_return(components)
    allow(Datadog).to receive(:send).with(:components, allow_initialization: false).and_return(components)
    allow(Datadog).to receive(:configuration).and_return(settings)
    allow(Datadog).to receive(:logger).and_return(logger)
    allow(logger).to receive(:warn)
    allow(components).to receive(:reconfigure_sampler)
    allow(telemetry).to receive(:client_configuration_change!)
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
  end

  after { component&.shutdown! }

  describe 'RC enables DI → method probe installs and fires' do
    let(:rc_payload_enable) { {'lib_config' => {'dynamic_instrumentation_enabled' => true}} }
    let(:rc_content) { instance_double(Datadog::Core::Remote::Configuration::Content) }

    before do
      allow(rc_content).to receive(:applied)
      allow(rc_content).to receive(:errored)
      allow(telemetry).to receive(:client_configuration_change!)
    end

    it 'starts the component when dynamic_instrumentation_enabled=true arrives' do
      expect(component).not_to be_nil
      expect(component.started?).to be false

      Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)

      expect(component.started?).to be true
      expect(rc_content).to have_received(:applied)
    end

    it 'activates code tracking when the enable signal arrives' do
      # activate_tracking is the precondition for line probes to work on
      # code loaded between enablement and the probe arrival. Verifying
      # the side effect directly without depending on tracking's runtime
      # state (which other tests in the suite may touch).
      expect(Datadog::DI).to receive(:activate_tracking)

      Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
    end

    context 'after the component is started, a LIVE_DEBUGGING method probe arrives' do
      # The implicit-enablement-specific assertion is that the RC enable
      # signal flips the receiver from "silently drops probes" (component
      # stopped) to "installs probes" (component started). The probe-fires
      # path beyond installation is regression-covered by
      # everything_from_remote_config_spec.rb and is not duplicated here.

      let(:probe_spec) do
        {
          id: 'test-probe-14',
          name: 'bar',
          type: 'LOG_PROBE',
          where: {
            typeName: 'ImplicitEnablementSpecTargetClass',
            methodName: 'target_method',
          },
        }
      end

      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
      let(:probe_configs) { {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec} }
      let(:transaction) do
        DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
      end
      let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

      before do
        allow(Datadog::DI).to receive(:component).and_return(component)
        allow(Datadog::DI).to receive(:activate_tracking)
      end

      it 'is silently dropped if delivered while the component is stopped' do
        expect(component.started?).to be false
        di_receiver.call(repository, transaction)
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 0
        expect(component.probe_manager.probe_repository.pending_probes.length).to eq 0
      end

      it 'is installed after the APM_TRACING enable signal arrives' do
        Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
        expect(component.started?).to be true

        di_receiver.call(repository, transaction)
        component.probe_notifier_worker.flush

        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
      end
    end
  end

  describe 'RC disable stops the component and unhooks probes' do
    let(:rc_payload_enable) { {'lib_config' => {'dynamic_instrumentation_enabled' => true}} }
    let(:rc_payload_disable) { {'lib_config' => {'dynamic_instrumentation_enabled' => false}} }
    let(:rc_content) { instance_double(Datadog::Core::Remote::Configuration::Content, applied: nil, errored: nil) }

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it 'stops the component when dynamic_instrumentation_enabled=false arrives' do
      Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
      expect(component.started?).to be true

      Datadog::Tracing::Remote.process_config(rc_payload_disable, rc_content)
      expect(component.started?).to be false
    end

    it 'is idempotent: false → false stays stopped without error' do
      Datadog::Tracing::Remote.process_config(rc_payload_disable, rc_content)
      expect(component.started?).to be false
      expect { Datadog::Tracing::Remote.process_config(rc_payload_disable, rc_content) }.not_to raise_error
      expect(component.started?).to be false
    end

    it 'supports restart: true → false → true' do
      Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
      expect(component.started?).to be true
      Datadog::Tracing::Remote.process_config(rc_payload_disable, rc_content)
      expect(component.started?).to be false
      Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
      expect(component.started?).to be true
    end

    context 'with an installed probe' do
      let(:probe_spec) do
        {
          id: 'test-probe-15',
          name: 'bar',
          type: 'LOG_PROBE',
          where: {
            typeName: 'ImplicitEnablementSpecTargetClass',
            methodName: 'target_method',
          },
        }
      end

      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
      let(:probe_configs) { {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec} }
      let(:transaction) do
        DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
      end
      let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

      before do
        allow(Datadog::DI).to receive(:component).and_return(component)
      end

      it 'unhooks the probe but preserves it in the repository when the component is stopped via RC disable' do
        Datadog::Tracing::Remote.process_config(rc_payload_enable, rc_content)
        di_receiver.call(repository, transaction)
        component.probe_notifier_worker.flush
        installed = component.probe_manager.probe_repository.installed_probes
        expect(installed.length).to eq 1
        probe = installed.values.first
        # Pre-check: hook installed instrumentation on the target method.
        expect(probe.instrumentation_module).not_to be_nil

        Datadog::Tracing::Remote.process_config(rc_payload_disable, rc_content)

        expect(component.started?).to be false
        # stop! calls probe_manager.stop which unhooks installed probes
        # without clearing the repository, so a subsequent RC re-enable
        # can re-hook the probe locally without waiting for the
        # LIVE_DEBUGGING content hash to change. See
        # ProbeManager#stop for the rationale.
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
        expect(component.probe_manager.probe_repository.installed_probes[probe.id]).to be(probe)
        # instrumentation_module is nilled by Instrumenter#unhook_method,
        # confirming the probe was unhooked on stop.
        expect(probe.instrumentation_module).to be_nil
      end
    end
  end

  describe 'combined RC transaction: LIVE_DEBUGGING + APM_TRACING dispatched together' do
    # Regression test for the dispatch-order bug: when a
    # single RC response contains both a LIVE_DEBUGGING probe insert AND an
    # APM_TRACING `dynamic_instrumentation_enabled=true` toggle, the receiver
    # registered first wins control of dispatch. If the DI receiver ran first
    # while the component is still stopped, it would silently drop the probe;
    # the Tracing receiver would then start DI, but the probe content is now
    # "unchanged" in the repository so a subsequent poll would not redispatch
    # it, and the probe would never install.
    #
    # The fix in lib/datadog/core/remote/client/capabilities.rb registers the
    # Tracing receiver before the DI receiver. This test drives the full
    # Capabilities-built receiver list against a single combined transaction
    # to verify the probe lands on one dispatch.

    let(:probe_spec) do
      {
        id: 'test-probe-combined',
        name: 'bar',
        type: 'LOG_PROBE',
        where: {
          typeName: 'ImplicitEnablementSpecTargetClass',
          methodName: 'target_method',
        },
      }
    end

    let(:apm_tracing_payload) { {'lib_config' => {'dynamic_instrumentation_enabled' => true}} }

    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
    let(:combined_configs) do
      {
        'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec,
        'datadog/2/APM_TRACING/lib_config/config' => apm_tracing_payload,
      }
    end
    let(:transaction) do
      DIHelpers::TestRemoteConfigGenerator.new(combined_configs).insert_transaction(repository)
    end

    # Production-built receiver list (Tracing before DI). Bypasses AppSec /
    # SymDB / OpenFeature by leaving their settings disabled in `settings`.
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry) }
    let(:dispatcher) { Datadog::Core::Remote::Dispatcher.new(capabilities.receivers) }

    before do
      allow(Datadog::DI).to receive(:component).and_return(component)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it 'installs the probe in a single dispatch (Tracing receiver enables DI first)' do
      expect(component.started?).to be false

      dispatcher.dispatch(transaction, repository)
      component.probe_notifier_worker.flush

      expect(component.started?).to be true
      expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
    end
  end

  describe 'probe delivered in an earlier poll while stopped, enable in a later poll' do
    # Regression test for the cross-poll edge case: a probe can land in
    # one RC poll while DI is stopped and the enable signal arrive in a *separate*
    # later poll. The DI receiver drops the probe while stopped, and
    # Core::Remote::Client#apply_config marks the now-unchanged probe content
    # `same` on the later poll, so it is never re-dispatched. handle_rc_enablement
    # reconciles against the current LIVE_DEBUGGING contents on the
    # stopped->started transition so the probe installs without the customer
    # having to edit it.

    let(:probe_spec) do
      {
        id: 'test-probe-earlier-poll',
        name: 'bar',
        type: 'LOG_PROBE',
        where: {
          typeName: 'ImplicitEnablementSpecTargetClass',
          methodName: 'target_method',
        },
      }
    end

    let(:transport) { double(Datadog::Core::Remote::Transport::Config) }
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry) }
    let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

    # Poll N: only the LIVE_DEBUGGING probe (DI still stopped).
    let(:poll_with_probe_only) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec}
      ).mock_response
    end

    # Poll N+1: the same (unchanged) probe plus the APM_TRACING enable signal.
    let(:poll_with_enable) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {
          'datadog/2/LIVE_DEBUGGING/foo/bar' => probe_spec,
          'datadog/2/APM_TRACING/lib_config/config' => {'lib_config' => {'dynamic_instrumentation_enabled' => true}},
        }
      ).mock_response
    end

    before do
      allow(Datadog::DI).to receive(:component).and_return(component)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it 'installs the probe once DI is enabled, without waiting for redelivery' do
      expect(component.started?).to be false

      # Poll N: probe arrives while DI is stopped — dropped, not in the repository.
      expect(transport).to receive(:send_config).and_return(poll_with_probe_only)
      client.sync
      expect(component.started?).to be false
      expect(component.probe_manager.probe_repository.installed_probes.length).to eq 0
      expect(component.probe_manager.probe_repository.pending_probes.length).to eq 0

      # Poll N+1: enable arrives; the probe content is unchanged so the DI
      # receiver is not re-invoked for it. The enable-path reconcile installs it.
      expect(transport).to receive(:send_config).and_return(poll_with_enable)
      client.sync
      component.probe_notifier_worker.flush

      expect(component.started?).to be true
      expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
      expect(component.probe_manager.probe_repository.installed_probes.keys).to include('test-probe-earlier-poll')
    end
  end
end
