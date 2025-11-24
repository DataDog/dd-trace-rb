require "spec_helper"
require "datadog/profiling/spec_helper"

require "datadog/profiling/tasks/setup"

RSpec.describe Datadog::Profiling::Tasks::Setup do
  subject(:task) { described_class.new }

  describe "#run" do
    subject(:run) { task.run }

    before do
      described_class::ACTIVATE_EXTENSIONS_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
    end

    it "actives the forking extension before setting up the at_fork hooks" do
      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:apply!).ordered
      expect(task).to receive(:setup_at_fork_hooks).ordered

      run
    end

    it "only sets up the extensions and hooks once, even across different instances" do
      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:apply!).once
      expect_any_instance_of(described_class).to receive(:setup_at_fork_hooks).once

      task.run
      task.run
      described_class.new.run
      described_class.new.run
    end
  end

  describe "#setup_at_fork_hooks" do
    subject(:setup_at_fork_hooks) { task.send(:setup_at_fork_hooks) }

    let(:at_fork_hook) do
      the_hook = nil

      expect(Datadog::Core::Utils::AtForkMonkeyPatch).to receive(:at_fork) do |stage, &block|
        expect(stage).to be :child

        the_hook = block
      end

      setup_at_fork_hooks

      expect(the_hook).to_not be nil

      the_hook
    end

    it "sets up an at_fork hook that restarts the profiler" do
      expect(Datadog::Profiling).to receive(:start_if_enabled)

      at_fork_hook.call
    end

    context "when there is an issue starting the profiler" do
      before do
        expect(Datadog::Profiling).to receive(:start_if_enabled).and_raise("Dummy exception")
        allow(Datadog.logger).to receive(:warn) # Silence logging during tests
      end

      it "does not raise any error" do
        at_fork_hook.call
      end

      it "logs an exception" do
        expect(Datadog.logger).to receive(:warn) do |&message|
          expect(message.call).to include("Dummy exception")
        end

        at_fork_hook.call
      end
    end
  end
end
