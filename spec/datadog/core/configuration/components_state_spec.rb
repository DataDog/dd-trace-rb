require "spec_helper"
require "datadog/core/configuration/components_state"

RSpec.describe Datadog::Core::Configuration::ComponentsState do
  describe "#di_implicitly_enabled?" do
    # The implicit-enablement carry-over: when Datadog.configure rebuilds
    # the components tree, the new Components inspects the old state to
    # decide whether to start the DI component. If the previous tree had
    # DI implicitly enabled by an RC signal, the new tree must start DI
    # too — otherwise reconfiguration silently disables the customer's
    # active probes.

    it "defaults to false when not provided" do
      state = described_class.new(telemetry_enabled: true, remote_started: false)
      expect(state.di_implicitly_enabled?).to be false
    end

    it "is false when constructed with false" do
      state = described_class.new(telemetry_enabled: true, remote_started: false, di_implicitly_enabled: false)
      expect(state.di_implicitly_enabled?).to be false
    end

    it "is true when constructed with true" do
      state = described_class.new(telemetry_enabled: true, remote_started: false, di_implicitly_enabled: true)
      expect(state.di_implicitly_enabled?).to be true
    end

    it "coerces truthy non-bool values to true" do
      state = described_class.new(telemetry_enabled: true, remote_started: false, di_implicitly_enabled: "yes")
      expect(state.di_implicitly_enabled?).to be true
    end

    it "coerces nil to false" do
      state = described_class.new(telemetry_enabled: true, remote_started: false, di_implicitly_enabled: nil)
      expect(state.di_implicitly_enabled?).to be false
    end
  end

  describe "#rc_enablement_signal_paths" do
    # The recorded enable-signal carrier paths ride on ComponentsState so
    # that a Datadog.configure rebuild hands them to the replacement DI
    # component. The withdrawal branch in Tracing::Remote.apply_lib_config
    # reads them to decide whether an APM_TRACING parse failure can mask a
    # withdrawn dynamic_instrumentation_enabled signal.

    let(:signal_path) do
      Datadog::Core::Remote::Configuration::Path.parse("datadog/1/APM_TRACING/lib_config/config")
    end

    it "defaults to an empty array when not provided" do
      state = described_class.new(telemetry_enabled: true, remote_started: false)
      expect(state.rc_enablement_signal_paths).to eq([])
    end

    it "returns the paths it was constructed with" do
      state = described_class.new(
        telemetry_enabled: true,
        remote_started: false,
        rc_enablement_signal_paths: [signal_path],
      )
      expect(state.rc_enablement_signal_paths).to eq([signal_path])
    end

    it "coerces nil to an empty array" do
      state = described_class.new(telemetry_enabled: true, remote_started: false, rc_enablement_signal_paths: nil)
      expect(state.rc_enablement_signal_paths).to eq([])
    end
  end
end
