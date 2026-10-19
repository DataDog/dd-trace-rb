require "spec_helper"
require "datadog/profiling/remote"

RSpec.describe Datadog::Profiling::Remote do
  let(:remote) { described_class }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:components) { instance_double(Datadog::Core::Configuration::Components) }

  before do
    allow(Datadog).to receive(:configuration).and_return(settings)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components, allow_initialization: false).and_return(components)
    allow(components).to receive(:reconfigure_profiler) if components
  end

  describe ".capabilities" do
    it "advertises nothing until a bit is allocated in libdatadog" do
      expect(remote.capabilities).to be_empty
    end
  end

  describe ".apply_lib_config" do
    subject(:apply_lib_config) { remote.apply_lib_config(lib_config) }

    context "when profiling_enabled is true" do
      let(:lib_config) { {"profiling_enabled" => true} }

      it "enables profiling at remote configuration precedence" do
        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(false).to(true)

        expect(settings.profiling.options[:enabled].send(:precedence_set))
          .to be Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
      end

      it "overrides an explicit local false" do
        settings.profiling.enabled = false

        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(false).to(true)
      end

      it "restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        apply_lib_config
      end

      it "reports the change to telemetry" do
        expect(apply_lib_config).to include(["DD_PROFILING_ENABLED", true])
      end
    end

    context "when profiling_enabled is false" do
      let(:lib_config) { {"profiling_enabled" => false} }

      before { settings.profiling.enabled = true }

      it "disables profiling and restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(true).to(false)
      end
    end

    context "when profiling_no_signals_workaround_enabled is set" do
      let(:lib_config) { {"profiling_no_signals_workaround_enabled" => true} }

      it "sets the workaround and restarts the profiler" do
        expect(components).to receive(:reconfigure_profiler)

        expect { apply_lib_config }
          .to change { settings.profiling.advanced.no_signals_workaround_enabled }.from(:auto).to(true)
      end

      it "reports the change to telemetry" do
        expect(apply_lib_config).to include(["DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED", true])
      end
    end

    context "when both keys are absent" do
      let(:lib_config) { {} }

      it "does not restart the profiler" do
        expect(components).to_not receive(:reconfigure_profiler)

        apply_lib_config
      end

      it "reverts settings previously set by remote configuration" do
        remote.apply_lib_config({"profiling_enabled" => true})

        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(true).to(false)
      end

      it "restores an explicit local value rather than the default" do
        settings.profiling.enabled = true
        remote.apply_lib_config({"profiling_enabled" => false})

        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(false).to(true)
      end

      it "reports nil values to telemetry" do
        expect(apply_lib_config).to contain_exactly(
          ["DD_PROFILING_ENABLED", nil],
          ["DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED", nil],
        )
      end
    end

    context "when the values match what is already configured" do
      let(:lib_config) { {"profiling_enabled" => true} }

      before { remote.apply_lib_config(lib_config) }

      it "does not restart the profiler again" do
        expect(components).to_not receive(:reconfigure_profiler)

        apply_lib_config
      end
    end

    context "when components are not built yet" do
      let(:components) { nil }
      let(:lib_config) { {"profiling_enabled" => true} }

      it "applies the setting without raising" do
        expect { apply_lib_config }.to change { settings.profiling.enabled }.from(false).to(true)
      end
    end
  end
end
