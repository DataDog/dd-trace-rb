require "spec_helper"
require "datadog/di/spec_helper"
require "datadog/di"

# Target class for the method probe used below. Loaded before the probe
# arrives so the probe installs immediately on the first RC poll.
class ProbeRemovalSpecTargetClass
  def target_method
    42
  end
end

RSpec.describe "DI probe removal via remote config" do
  di_test
  deactivate_code_tracking

  # Drives the full RC machinery (Core::Remote::Client + DI::Remote receiver +
  # real DI::Component) across two polls: the first delivers a method probe
  # that installs and hooks the target, the second drops it from RC and the
  # DI receiver removes the probe and unhooks the instrumentation.

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:agent_settings) { instance_double_agent_settings_with_stubs }
  let(:logger) { logger_allowing_debug }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  # Replace the probe notifier worker transports with doubles so probe status
  # and snapshot delivery does not attempt real network calls.
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

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger, telemetry: telemetry).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
      component.start!
    end
  end

  let(:transport) { instance_double(Datadog::Core::Remote::Transport::Config::Transport) }
  let(:capabilities) { Datadog::Core::Remote::Client::Capabilities.new(settings, telemetry) }
  let(:client) { Datadog::Core::Remote::Client.new(transport, capabilities, settings: settings, logger: logger) }

  let(:probe_spec) do
    {id: "test-probe-removal", name: "bar", type: "LOG_PROBE",
     where: {typeName: "ProbeRemovalSpecTargetClass", methodName: "target_method"}}
  end

  let(:probe_configs) do
    {"datadog/2/LIVE_DEBUGGING/foo/bar" => probe_spec}
  end

  let(:response_with_probe) do
    DIHelpers::TestRemoteConfigGenerator.new(probe_configs).mock_response
  end

  # Second poll: the probe is gone from RC.
  let(:empty_rc_response) do
    DIHelpers::TestRemoteConfigGenerator.new({}).mock_response
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(Datadog::DI).to receive(:component) { component }
  end

  after { component.shutdown! }

  def install_probe
    expect(transport).to receive(:send_config).and_return(response_with_probe)
    client.sync
    component.probe_notifier_worker.flush
  end

  def remove_probe
    expect(transport).to receive(:send_config).and_return(empty_rc_response)
    client.sync
    component.probe_notifier_worker.flush
  end

  it "removes the probe and unhooks instrumentation when it disappears from RC" do
    install_probe

    installed = component.probe_manager.probe_repository.installed_probes
    expect(installed.length).to eq 1
    probe = installed.values.first
    expect(probe.instrumentation_module).not_to be_nil
    expect(Datadog::DI.instrumented_count).to eq 1

    remove_probe

    expect(component.probe_manager.probe_repository.installed_probes.length).to eq 0
    expect(component.probe_manager.probe_repository.pending_probes.length).to eq 0
    expect(probe.instrumentation_module).to be_nil
    expect(Datadog::DI.instrumented_count).to eq 0
  end

  it "captures a snapshot while the probe is installed" do
    install_probe

    ProbeRemovalSpecTargetClass.new.target_method
    component.probe_notifier_worker.flush

    expect(input_transport).to have_received(:send_input).at_least(:once)
  end

  it "stops capturing snapshots after the probe is removed" do
    install_probe
    remove_probe

    ProbeRemovalSpecTargetClass.new.target_method
    component.probe_notifier_worker.flush

    expect(input_transport).not_to have_received(:send_input)
  end
end
