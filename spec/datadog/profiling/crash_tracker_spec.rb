require 'datadog/profiling/spec_helper'
require 'datadog/profiling/crash_tracker'

RSpec.describe Datadog::Profiling::CrashTracker do
  before { skip_if_profiling_not_supported(self) }

  describe '.build_crash_tracker' do
    let(:path_to_crashtracking_receiver_binary) { :the_path_to_crashtracking_receiver_binary }

    subject(:build_crash_tracker) do
      described_class.build_crash_tracker(
        exporter_configuration: :the_exporter_configuration,
        path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
        tags: { 'tag1' => 'value1', 'tag2' => 'value2' },
      )
    end

    it 'starts the crash tracker' do
      expect(described_class).to receive(:_native_start_crashtracker).with(
        exporter_configuration: :the_exporter_configuration,
        path_to_crashtracking_receiver_binary: :the_path_to_crashtracking_receiver_binary,
        tags_as_array: [['tag1', 'value1'], ['tag2', 'value2']],
      )

      build_crash_tracker
    end

    it 'returns the crash tracker instance' do
      expect(described_class).to receive(:_native_start_crashtracker)

      expect(build_crash_tracker).to be_an_instance_of(described_class)
    end

    it 'logs a debug message' do
      expect(described_class).to receive(:_native_start_crashtracker)

      expect(Datadog.logger).to receive(:debug).with('Crash tracker enabled')

      build_crash_tracker
    end

    context 'when no path_to_crashtracking_receiver_binary is provided' do
      before do
        expect(Libdatadog).to receive(:path_to_crashtracking_receiver_binary).and_return(:the_libdatadog_receiver_path)
      end

      it 'uses the path_to_crashtracking_receiver_binary provided by libdatadog' do
        expect(described_class).to receive(:_native_start_crashtracker).with(
          exporter_configuration: :the_exporter_configuration,
          path_to_crashtracking_receiver_binary: :the_libdatadog_receiver_path,
          tags_as_array: [['tag1', 'value1'], ['tag2', 'value2']],
        )

        described_class.build_crash_tracker(
          exporter_configuration: :the_exporter_configuration,
          tags: { 'tag1' => 'value1', 'tag2' => 'value2' },
        )
      end
    end

    context 'when crash tracker raises an exception during start' do
      before do
        expect(described_class).to receive(:_native_start_crashtracker) { raise 'Test failure' }
        allow(Datadog.logger).to receive(:error)
      end

      it 'logs the exception as an error' do
        expect(Datadog.logger).to receive(:error).with(/Test failure/)

        build_crash_tracker
      end

      it { is_expected.to be nil }
    end

    context 'when the path_to_crashtracking_receiver_binary is nil' do
      let(:path_to_crashtracking_receiver_binary) { nil }

      before { allow(Datadog.logger).to receive(:warn) }

      it 'logs the exception as a warn' do
        expect(Datadog.logger).to receive(:warn).with(/Cannot enable profiling crash tracking/)

        build_crash_tracker
      end

      it { is_expected.to be nil }
    end

    context 'when started twice' do
      it 'works successfully' do
        2.times { described_class.new(exporter_configuration: [:agent, 'http://localhost:1234'], tags_as_array: [], path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary) }
      end
    end
  end

  # TODO: Maybe add an integration spec that triggers a segfault in a fork?
end
