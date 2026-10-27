require "spec_helper"
require "datadog/di/spec_helper"
require "datadog/di"
require "datadog/statsd"
require "datadog/tracing/remote"

# Target class for the method probe used below. Loaded before the RC
# enable signal arrives — this is the canonical "code loaded before
# enablement" case that always-build + late activation is meant to fix.
class ImplicitEnablementSpecTargetClass
  def target_method
    42
  end
end

RSpec.describe "DI implicit enablement integration" do
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

  let(:explicit_opt_in_settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.remote.enabled = true
      s.dynamic_instrumentation.enabled = true
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
    # Tracing::Remote.apply_lib_config replays (resume_pending_upload) or stops
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

  let(:remote) do
    instance_double(Datadog::Core::Remote::Component, add_products: nil, remove_products: nil)
  end

  let(:components) do
    # Stand-in for Core::Configuration::Components. handle_rc_enablement
    # reaches the component via Datadog.send(:components).dynamic_instrumentation
    # and Tracing::Remote.apply_lib_config calls reconfigure_sampler on it for
    # each tracing dynamic-option update. We expose only what's needed.
    instance_double(
      Datadog::Core::Configuration::Components,
      dynamic_instrumentation: component,
      telemetry: telemetry,
      symbol_database: symbol_database,
      remote: remote,
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

  def stub_di_rc_environment
    allow(Datadog::DI).to receive(:activate_tracking)
    allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(true)
  end

  # Drives the production RC dispatch path (Tracing::Remote.merge_and_apply_configs)
  # for a single APM_TRACING payload, returning the Content so apply_state can
  # be asserted.
  def apply_rc_payload(payload)
    apply_rc_content(JSON.dump(payload))
  end

  def apply_rc_content(raw_content)
    content = Datadog::Core::Remote::Configuration::Content.parse(
      {
        path: "datadog/1/APM_TRACING/lib_config/config",
        content: raw_content,
      },
    )
    repository = instance_double(
      Datadog::Core::Remote::Configuration::Repository,
      contents: [content],
    )
    Datadog::Tracing::Remote.merge_and_apply_configs(repository)
    content
  end

  describe "RC enables DI → method probe installs and fires" do
    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

    before do
      allow(telemetry).to receive(:client_configuration_change!)
    end

    it "starts the component when dynamic_instrumentation_enabled=true arrives" do
      expect(component).not_to be_nil
      expect(component.started?).to be false

      content = apply_rc_payload(rc_payload_enable)

      expect(component.started?).to be true
      expect(content.apply_state).to eq(2)
    end

    it "advertises the DI products via remote config once the component starts" do
      # End-to-end: the enable signal starts the real component, and only then
      # does the product become advertised. supported_runtime? is pinned so the
      # deferred Symbol Database product is deterministic across Ruby versions.
      allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(true)
      expect(component.started?).to be false
      expect(remote).to receive(:add_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

      apply_rc_payload(rc_payload_enable)

      expect(component.started?).to be true
    end

    it "activates code tracking when the enable signal arrives" do
      # activate_tracking is the precondition for line probes to work on
      # code loaded between enablement and the probe arrival. Verifying
      # the side effect directly without depending on tracking's runtime
      # state (which other tests in the suite may touch).
      expect(Datadog::DI).to receive(:activate_tracking)

      apply_rc_payload(rc_payload_enable)
    end

    context "after the component is started, a LIVE_DEBUGGING method probe arrives" do
      # The implicit-enablement-specific assertion is that the RC enable
      # signal flips the receiver from "silently drops probes" (component
      # stopped) to "installs probes" (component started). The probe-fires
      # path beyond installation is regression-covered by
      # everything_from_remote_config_spec.rb and is not duplicated here.

      let(:probe_spec) do
        {
          id: "test-probe-14",
          name: "bar",
          type: "LOG_PROBE",
          where: {
            typeName: "ImplicitEnablementSpecTargetClass",
            methodName: "target_method",
          },
        }
      end

      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
      let(:probe_configs) { {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec} }
      let(:transaction) do
        DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
      end
      let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

      before do
        allow(Datadog::DI).to receive(:component).and_return(component)
        allow(Datadog::DI).to receive(:activate_tracking)
      end

      it "is silently dropped if delivered while the component is stopped" do
        expect(component.started?).to be false
        di_receiver.call(repository, transaction)
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 0
        expect(component.probe_manager.probe_repository.pending_probes.length).to eq 0
      end

      it "is installed after the APM_TRACING enable signal arrives" do
        apply_rc_payload(rc_payload_enable)
        expect(component.started?).to be true

        di_receiver.call(repository, transaction)
        component.probe_notifier_worker.flush

        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
      end
    end
  end

  describe "RC disable stops the component and unhooks probes" do
    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }
    let(:rc_payload_disable) { {"lib_config" => {"dynamic_instrumentation_enabled" => false}} }

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it "stops the component when dynamic_instrumentation_enabled=false arrives" do
      apply_rc_payload(rc_payload_enable)
      expect(component.started?).to be true

      apply_rc_payload(rc_payload_disable)
      expect(component.started?).to be false
    end

    it "is idempotent: false → false stays stopped without error" do
      apply_rc_payload(rc_payload_disable)
      expect(component.started?).to be false
      expect { apply_rc_payload(rc_payload_disable) }.not_to raise_error
      expect(component.started?).to be false
    end

    it "supports restart: true → false → true" do
      apply_rc_payload(rc_payload_enable)
      expect(component.started?).to be true
      apply_rc_payload(rc_payload_disable)
      expect(component.started?).to be false
      apply_rc_payload(rc_payload_enable)
      expect(component.started?).to be true
    end

    context "with an installed probe" do
      let(:probe_spec) do
        {
          id: "test-probe-15",
          name: "bar",
          type: "LOG_PROBE",
          where: {
            typeName: "ImplicitEnablementSpecTargetClass",
            methodName: "target_method",
          },
        }
      end

      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
      let(:probe_configs) { {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec} }
      let(:transaction) do
        DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
      end
      let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

      before do
        allow(Datadog::DI).to receive(:component).and_return(component)
      end

      it "unhooks the probe but preserves it in the repository when the component is stopped via RC disable" do
        apply_rc_payload(rc_payload_enable)
        di_receiver.call(repository, transaction)
        component.probe_notifier_worker.flush
        installed = component.probe_manager.probe_repository.installed_probes
        expect(installed.length).to eq 1
        probe = installed.values.first
        # Pre-check: hook installed instrumentation on the target method.
        expect(probe.instrumentation_module).not_to be_nil

        apply_rc_payload(rc_payload_disable)

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

    context "with an installed probe that the backend deletes while DI is stopped" do
      let(:probe_spec) do
        {
          id: "test-probe-deleted-while-stopped",
          name: "bar",
          type: "LOG_PROBE",
          where: {
            typeName: "ImplicitEnablementSpecTargetClass",
            methodName: "target_method",
          },
        }
      end

      let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
      let(:probe_configs) { {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec} }
      let(:transaction) do
        DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
      end
      let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

      it "does not reinstall the probe when RC re-enables DI" do
        apply_rc_payload(rc_payload_enable)
        di_receiver.call(repository, transaction)
        component.probe_notifier_worker.flush
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1

        apply_rc_payload(rc_payload_disable)
        expect(component.started?).to be false
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1

        deletion = repository.transaction do |current, txn|
          current.paths.each { |path| txn.delete(path) }
        end
        di_receiver.call(repository, deletion)
        expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1

        apply_rc_payload(rc_payload_enable)

        expect(component.started?).to be true
        expect(component.probe_manager.probe_repository.installed_probes).to be_empty
        expect(component.probe_manager.probe_repository.pending_probes).to be_empty
        expect(Datadog::DI.instrumented_count).to eq 0
      end
    end
  end

  describe "combined RC transaction: LIVE_DEBUGGING + APM_TRACING dispatched together" do
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
        id: "test-probe-combined",
        name: "bar",
        type: "LOG_PROBE",
        where: {
          typeName: "ImplicitEnablementSpecTargetClass",
          methodName: "target_method",
        },
      }
    end

    let(:apm_tracing_payload) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
    let(:combined_configs) do
      {
        "datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec,
        "datadog/2/APM_TRACING/lib_config/config" => apm_tracing_payload,
      }
    end
    let(:transaction) do
      DIHelpers::TestRemoteConfigGenerator.new(combined_configs).insert_transaction(repository)
    end

    # Production-built receiver list (Tracing before DI). Bypasses AppSec /
    # SymDB / OpenFeature by leaving their settings disabled in `settings`.
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry: telemetry) }
    let(:dispatcher) { Datadog::Core::Remote::Dispatcher.new(capabilities.receivers) }

    before do
      allow(Datadog::DI).to receive(:component).and_return(component)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it "installs the probe in a single dispatch (Tracing receiver enables DI first)" do
      expect(component.started?).to be false

      dispatcher.dispatch(transaction, repository)
      component.probe_notifier_worker.flush

      expect(component.started?).to be true
      expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1
    end
  end

  describe "probe delivered in an earlier poll while stopped, enable in a later poll" do
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
        id: "test-probe-earlier-poll",
        name: "bar",
        type: "LOG_PROBE",
        where: {
          typeName: "ImplicitEnablementSpecTargetClass",
          methodName: "target_method",
        },
      }
    end

    let(:transport) { instance_double(Datadog::Core::Remote::Transport::Config::Transport) }
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry: telemetry) }
    let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

    # Poll N: only the LIVE_DEBUGGING probe (DI still stopped).
    let(:poll_with_probe_only) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec},
      ).mock_response
    end

    # Poll N+1: the same (unchanged) probe plus the APM_TRACING enable signal.
    let(:poll_with_enable) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {
          "datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec,
          "datadog/2/APM_TRACING/lib_config/config" => {"lib_config" => {"dynamic_instrumentation_enabled" => true}},
        },
      ).mock_response
    end

    before do
      allow(Datadog::DI).to receive(:component).and_return(component)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    it "installs the probe once DI is enabled, without waiting for redelivery" do
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
      expect(component.probe_manager.probe_repository.installed_probes.keys).to include("test-probe-earlier-poll")
    end
  end

  describe "RC enables DI via merged org/env-level (multi-config) configs" do
    def apm_content(config_id, hash)
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/APM_TRACING/#{config_id}/lib_config",
          content: JSON.dump(hash),
        },
      )
    end

    # service/env set at construction (not in-place mutation) so config_matches?
    # can resolve the service+env target below.
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |s|
        s.remote.enabled = true
        s.dynamic_instrumentation.internal.development = true
        s.dynamic_instrumentation.internal.propagate_all_exceptions = true
        s.service = "web"
        s.env = "prod"
      end
    end

    let(:repository) do
      instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents)
    end

    before { allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(true) }

    def build_repository(*hashes)
      instance_double(
        Datadog::Core::Remote::Configuration::Repository,
        contents: hashes.each_with_index.map { |h, i| apm_content("c#{i}", h) },
      )
    end

    context "with a single org-wide enable" do
      let(:contents) do
        [apm_content("org", {"service_target" => {"service" => "*", "env" => "*"},
          "lib_config" => {"dynamic_instrumentation_enabled" => true}})]
      end

      it "starts the component end-to-end" do
        expect(component.started?).to be false

        Datadog::Tracing::Remote.merge_and_apply_configs(repository)

        expect(component.started?).to be true
        expect(contents.first.apply_state).to eq(2)
      end
    end

    context "when a service+env override disables what the org-wide config enables" do
      let(:contents) do
        [
          apm_content("org", {"service_target" => {"service" => "*", "env" => "*"},
            "lib_config" => {"dynamic_instrumentation_enabled" => true}}),
          apm_content("svc", {"service_target" => {"service" => "web", "env" => "prod"},
            "lib_config" => {"dynamic_instrumentation_enabled" => false}}),
        ]
      end

      it "does not start the component (most-specific false wins) and marks both applied" do
        expect(component.started?).to be false

        Datadog::Tracing::Remote.merge_and_apply_configs(repository)

        expect(component.started?).to be false
        expect(contents.map(&:apply_state)).to eq([2, 2])
      end
    end

    it "stops the component when a later merge resolves to false" do
      Datadog::Tracing::Remote.merge_and_apply_configs(
        build_repository({"service_target" => {"service" => "*", "env" => "*"},
          "lib_config" => {"dynamic_instrumentation_enabled" => true}}),
      )
      expect(component.started?).to be true

      Datadog::Tracing::Remote.merge_and_apply_configs(
        build_repository(
          {"service_target" => {"service" => "*", "env" => "*"},
           "lib_config" => {"dynamic_instrumentation_enabled" => true}},
          {"service_target" => {"service" => "web", "env" => "prod"},
           "lib_config" => {"dynamic_instrumentation_enabled" => false}},
        ),
      )
      expect(component.started?).to be false
    end

    it "inherits dynamic_instrumentation_enabled from org when the service+env config supplies only a sampling rate" do
      Datadog::Tracing::Remote.merge_and_apply_configs(
        build_repository(
          {"service_target" => {"service" => "*", "env" => "*"},
           "lib_config" => {"dynamic_instrumentation_enabled" => true}},
          {"service_target" => {"service" => "web", "env" => "prod"},
           "lib_config" => {"tracing_sampling_rate" => 0.5}},
        ),
      )
      expect(component.started?).to be true
    end
  end

  describe "RC withdraws the dynamic_instrumentation_enabled signal (config deleted)" do
    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }
    let(:rc_payload_without_di) { {"lib_config" => {"tracing_sampling_rate" => 0.5}} }

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      stub_di_rc_environment
    end

    context "when DI was started solely from RC enablement" do
      before do
        apply_rc_payload(rc_payload_enable)
        expect(component.started?).to be true
        expect(component.implicitly_enabled?).to be true
      end

      it "is started by the RC enable signal" do
        expect(component.started?).to be true
      end

      it "stops the component and withdraws the DI products when the signal is withdrawn" do
        expect(remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

        apply_rc_payload(rc_payload_without_di)

        expect(component.started?).to be false
      end
    end

    context "when DI was started by an explicit customer opt-in" do
      let(:settings) { explicit_opt_in_settings }

      before do
        component.start!
        expect(component.started?).to be true
        expect(component.implicitly_enabled?).to be false
      end

      it "is started by the explicit opt-in and is not implicitly enabled" do
        expect(component.started?).to be true
        expect(component.implicitly_enabled?).to be false
      end

      it "leaves the component started and does not withdraw products when the signal is withdrawn" do
        expect(remote).not_to receive(:remove_products)
        expect(Datadog::DI::Remote).not_to receive(:handle_rc_enablement)

        apply_rc_payload(rc_payload_without_di)

        expect(component.started?).to be true
      end
    end
  end

  describe "RC replaces the enable config with a payload that fails to parse" do
    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

    before do
      stub_di_rc_environment
      allow(telemetry).to receive(:report)

      apply_rc_payload(rc_payload_enable)
      expect(component.started?).to be true
    end

    it "leaves the component started and marks the payload errored" do
      expect(remote).not_to receive(:remove_products)

      content = apply_rc_content("{not json")

      expect(component.started?).to be true
      expect(content.apply_state).to eq(3)
    end
  end

  describe "RC withdraws the enable signal while an unrelated APM_TRACING config fails to parse" do
    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }
    let(:malformed_unrelated) do
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/APM_TRACING/unrelated/lib_config",
          content: "{not json",
        },
      )
    end
    let(:repository) do
      instance_double(
        Datadog::Core::Remote::Configuration::Repository,
        contents: [malformed_unrelated],
      )
    end

    before do
      stub_di_rc_environment
      allow(telemetry).to receive(:report)

      apply_rc_payload(rc_payload_enable)
      expect(component.started?).to be true
    end

    it "stops the component and withdraws the DI products, marking the unrelated config errored" do
      expect(remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

      Datadog::Tracing::Remote.merge_and_apply_configs(repository)

      expect(component.started?).to be false
      expect(malformed_unrelated.apply_state).to eq(3)
    end
  end

  describe "RC withdraws the enable signal after a Datadog.configure rebuild, with an unrelated parse failure" do
    let(:rebuild_remote) do
      instance_double(
        Datadog::Core::Remote::Component,
        start: nil, started?: false, shutdown!: nil,
        add_products: nil, remove_products: nil
      )
    end
    let(:rebuild_telemetry) do
      instance_double(
        Datadog::Core::Telemetry::Component,
        start: nil, enabled: false, shutdown!: nil, emit_closing!: nil,
        integrations_change!: nil
      )
    end
    # Both trees share this double so the old tree's shutdown sees the
    # replacement still using it and skips closing it.
    let(:rebuild_statsd) { instance_double(Datadog::Statsd, close: nil) }
    let(:unrelated_malformed_content) do
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/APM_TRACING/unrelated/lib_config",
          content: "{not json",
        },
      )
    end
    let(:withdrawal_repository) do
      instance_double(
        Datadog::Core::Remote::Configuration::Repository,
        contents: [unrelated_malformed_content],
      )
    end

    before do
      # Dispatch RC against the real component tree that Datadog.configure installs.
      allow(Datadog).to receive(:send).with(:components, allow_initialization: false).and_call_original

      allow(Datadog::Core::Remote::Component).to receive(:new).and_return(rebuild_remote)
      allow(Datadog::Core::Telemetry::Component).to receive(:new).and_return(rebuild_telemetry)
      allow(Datadog::Statsd).to receive(:new).and_return(rebuild_statsd)
      allow(Datadog::SymbolDatabase::Component).to receive(:build).and_return(nil)
      allow(Datadog::SymbolDatabase).to receive(:supported_runtime?).and_return(true)
      allow(Datadog::Core::ProcessDiscovery).to receive(:publish)
      allow(Datadog::Core::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!)
      allow(Datadog::DI).to receive(:activate_tracking)
      allow(rebuild_telemetry).to receive(:report)
      allow(rebuild_telemetry).to receive(:client_configuration_change!)
    end

    after do
      # Shut down the installed trees while the doubles above still respond, before the global reset.
      Datadog.send(:reset!)
    end

    def current_components
      Datadog.send(:components, allow_initialization: false)
    end

    it "stops the rebuilt component and withdraws the DI products" do
      expect(current_components).to be nil

      Datadog.configure {}

      first_tree_di = current_components.dynamic_instrumentation
      expect(first_tree_di).not_to be_nil
      expect(first_tree_di.started?).to be false

      apply_rc_payload({"lib_config" => {"dynamic_instrumentation_enabled" => true}})

      expect(first_tree_di.started?).to be true
      recorded_paths = first_tree_di.rc_enablement_signal_paths
      expect(recorded_paths).not_to be_empty

      Datadog.configure {}

      rebuilt_di = current_components.dynamic_instrumentation
      expect(rebuilt_di).not_to be(first_tree_di)
      expect(rebuilt_di.implicitly_enabled?).to be true
      expect(rebuilt_di.rc_enablement_signal_paths).to eq(recorded_paths)

      expect(rebuild_remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

      Datadog::Tracing::Remote.merge_and_apply_configs(withdrawal_repository)

      expect(rebuilt_di.started?).to be false
      expect(unrelated_malformed_content.apply_state).to eq(3)
    end
  end

  describe "RC withdraws the enable signal while no client holds it (fresh client)" do
    let(:transport) { instance_double(Datadog::Core::Remote::Transport::Config::Transport) }
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry: telemetry) }
    let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

    let(:poll_without_enable) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {"datadog/2/ASM_DATA/blocked_ips/config" => {"rules_data" => []}},
      ).mock_response
    end

    let(:empty_poll) do
      instance_double(Datadog::Core::Remote::Transport::HTTP::Config::Response, ok?: true, empty?: true)
    end

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      stub_di_rc_environment
    end

    context "when DI was started solely from RC enablement" do
      before do
        apply_rc_payload(rc_payload_enable)
        expect(component.started?).to be true
        expect(component.implicitly_enabled?).to be true
      end

      it "stops the component and withdraws the DI products on the first sync" do
        expect(remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")
        expect(transport).to receive(:send_config).and_return(poll_without_enable)

        client.sync

        expect(component.started?).to be false
      end

      it "keeps the component started on an empty first response and stops it on the next response that carries targets" do
        expect(transport).to receive(:send_config).twice.and_return(empty_poll, poll_without_enable)

        client.sync

        expect(component.started?).to be true

        expect(remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

        client.sync

        expect(component.started?).to be false
      end
    end

    context "when DI was started by an explicit customer opt-in" do
      let(:settings) { explicit_opt_in_settings }

      before do
        component.start!
        expect(component.started?).to be true
        expect(component.implicitly_enabled?).to be false
      end

      it "leaves the component started on the first sync" do
        expect(transport).to receive(:send_config).and_return(poll_without_enable)
        client.sync

        expect(component.started?).to be true
      end
    end
  end

  describe "RC delivers enablement changes across sequential merges over two carriers" do
    def apm_content(config_id, raw_content)
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/APM_TRACING/#{config_id}/lib_config",
          content: raw_content,
        },
      )
    end

    def repository_with(*contents)
      instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents)
    end

    let(:enable) { JSON.dump("lib_config" => {"dynamic_instrumentation_enabled" => true}) }
    let(:no_di_field) { JSON.dump("lib_config" => {"tracing_sampling_rate" => 0.5}) }
    let(:malformed) { "{not json" }

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      allow(telemetry).to receive(:report)
      stub_di_rc_environment
    end

    it "keeps the DI state when the carrier deleted last was replaced by malformed content" do
      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", enable), apm_content("b", enable)),
      )
      expect(component.started?).to be true

      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", malformed), apm_content("b", enable)),
      )
      expect(component.started?).to be true

      expect(remote).not_to receive(:remove_products)

      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", malformed)),
      )

      expect(component.started?).to be true
    end

    it "stops DI when the carrier validly dropped the field before its replacement failed to parse" do
      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", enable), apm_content("b", enable)),
      )
      expect(component.started?).to be true

      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", no_di_field), apm_content("b", malformed)),
      )
      expect(component.started?).to be true

      expect(remote).to receive(:remove_products).with("LIVE_DEBUGGING", "LIVE_DEBUGGING_SYMBOL_DB")

      Datadog::Tracing::Remote.merge_and_apply_configs(
        repository_with(apm_content("a", malformed)),
      )

      expect(component.started?).to be false
    end
  end

  describe "RC withdraws a LIVE_DEBUGGING probe while no client holds it (fresh client)" do
    let(:probe_spec) do
      {
        id: "test-probe-fresh-client-removal",
        name: "bar",
        type: "LOG_PROBE",
        where: {
          typeName: "ImplicitEnablementSpecTargetClass",
          methodName: "target_method",
        },
      }
    end

    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
    let(:probe_configs) { {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec} }
    let(:transaction) do
      DIHelpers::TestRemoteConfigGenerator.new(probe_configs).insert_transaction(repository)
    end
    let(:di_receiver) { Datadog::DI::Remote.receivers(telemetry).first }

    let(:transport) { instance_double(Datadog::Core::Remote::Transport::Config::Transport) }
    let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry: telemetry) }
    let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

    let(:rc_payload_enable) { {"lib_config" => {"dynamic_instrumentation_enabled" => true}} }

    let(:poll_without_probe) do
      DIHelpers::TestRemoteConfigGenerator.new(
        {"datadog/2/APM_TRACING/lib_config/config" => rc_payload_enable},
      ).mock_response
    end

    before do
      allow(telemetry).to receive(:client_configuration_change!)
      stub_di_rc_environment
    end

    it "uninstalls the probe on the fresh client's first sync" do
      apply_rc_payload(rc_payload_enable)
      di_receiver.call(repository, transaction)
      component.probe_notifier_worker.flush
      expect(component.probe_manager.probe_repository.installed_probes.length).to eq 1

      expect(transport).to receive(:send_config).and_return(poll_without_probe)

      client.sync
      component.probe_notifier_worker.flush

      expect(component.probe_manager.probe_repository.installed_probes).to be_empty
      expect(Datadog::DI.instrumented_count).to eq 0
      expect(component.started?).to be true
    end
  end
end
