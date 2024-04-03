require 'spec_helper'
require 'datadog/profiling'

RSpec.describe Datadog::Profiling do
  describe '.start_if_enabled' do
    subject(:start_if_enabled) { described_class.start_if_enabled }

    before do
      allow(Datadog.send(:components)).to receive(:profiler).and_return(result)
    end

    context 'with the profiler instance available' do
      let(:result) { instance_double('Datadog::Profiling::Profiler') }
      it 'starts the profiler instance' do
        expect(result).to receive(:start)
        is_expected.to be(true)
      end
    end

    context 'with the profiler instance not available' do
      let(:result) { nil }
      it { is_expected.to be(false) }
    end
  end

  describe '.allocation_count' do
    subject(:allocation_count) { described_class.allocation_count }

    context 'when profiling is supported' do
      before do
        skip('Test only runs on setups where profiling is supported') unless described_class.supported?
      end

      it 'delegates to the CpuAndWallTimeWorker' do
        expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
          .to receive(:_native_allocation_count).and_return(:allocation_count_result)

        expect(allocation_count).to be :allocation_count_result
      end
    end

    context 'when profiling is not supported' do
      before do
        skip('Test only runs on setups where profiling is not supported') if described_class.supported?
      end

      it 'does not reference the CpuAndWallTimeWorker' do
        if defined?(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
          without_partial_double_verification do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to_not receive(:_native_allocation_count)
          end
        end

        allocation_count
      end

      it { is_expected.to be nil }
    end
  end

  describe '.enabled?' do
    subject(:enabled?) { described_class.enabled? }

    before do
      allow(Datadog.send(:components)).to receive(:profiler).and_return(profiler)
    end

    context 'when no profiler is available' do
      let(:profiler) { nil }

      it { is_expected.to be(false) }
    end

    context 'when a profiler is available' do
      let(:profiler) { instance_double('Datadog::Profiling::Profiler', scheduler: scheduler) }
      let(:scheduler) { instance_double('Datadog::Profiling::Scheduler', running?: running) }

      context 'when the profiler is running' do
        let(:running) { true }
        it { is_expected.to be(true) }
      end

      context 'when the profiler is not running' do
        let(:running) { false }
        it { is_expected.to be(false) }
      end
    end
  end

  describe '.wait_until_running' do
    subject(:wait_until_running) { described_class.wait_until_running }

    before do
      allow(Datadog.send(:components)).to receive(:profiler).and_return(profiler)
    end

    context 'when no profiler is available' do
      let(:profiler) { nil }

      it 'raises an error' do
        expect { wait_until_running }.to raise_error(/Profiler not enabled or available/)
      end
    end

    context 'when a profiler is available' do
      let(:profiler) { instance_double('Datadog::Profiling::Profiler', worker: worker) }
      let(:worker) do
        instance_double('Datadog::Profiling::Collectors::CpuAndWallTimeWorker', wait_until_running: worker_result)
      end

      context 'when the worker is ready' do
        let(:worker_result) { true }
        it { is_expected.to be(true) }
      end

      context 'when the worker times out' do
        let(:worker_result) { nil }

        before { expect(worker).to receive(:wait_until_running).and_raise(StandardError.new('Timeout')) }

        it 'raises an error' do
          expect { wait_until_running }.to raise_error(/Timeout/)
        end
      end
    end
  end

  describe '::supported?' do
    subject(:supported?) { described_class.supported? }

    context 'when there is an unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return('Unsupported, sorry :(') }

      it { is_expected.to be false }
    end

    context 'when there is no unsupported_reason' do
      before { allow(described_class).to receive(:unsupported_reason).and_return(nil) }

      it { is_expected.to be true }
    end
  end

  describe '::unsupported_reason' do
    subject(:unsupported_reason) { described_class.unsupported_reason }

    context 'when the profiling native library was not compiled' do
      before do
        expect(described_class).to receive(:try_reading_skipped_reason_file).and_return('fake skipped reason')
      end

      it { is_expected.to include 'missing support for the Continuous Profiler' }
    end

    context 'when the profiling native library was compiled' do
      before do
        expect(described_class).to receive(:try_reading_skipped_reason_file).and_return nil
      end

      context 'when the profiling native library fails to be loaded with a exception' do
        let(:loaderror) do
          begin
            raise LoadError, 'Simulated require failure'
          rescue LoadError => e
            e
          end
        end

        before do
          expect(described_class).to receive(:try_loading_native_library).and_return([false, loaderror])
        end

        it { is_expected.to include 'error loading the profiling native extension' }
      end

      context "when the profiling native library fails to be loaded but there's no exception" do
        before do
          expect(described_class).to receive(:try_loading_native_library).and_return([false, nil])
        end

        it { is_expected.to include 'profiling native extension did not load correctly' }
      end

      context 'when the profiling native library is available' do
        before do
          expect(described_class).to receive(:try_loading_native_library).and_return([true, nil])
        end

        it { is_expected.to be nil }
      end
    end
  end

  describe '::try_loading_native_library' do
    subject(:try_loading_native_library) { described_class.send(:try_loading_native_library) }

    let(:native_extension_require_relative) { 'profiling/load_native_extension' }

    context 'when the profiling native library loads successfully' do
      before do
        expect(described_class)
          .to receive(:require_relative)
          .with(native_extension_require_relative)
        stub_const('Datadog::Profiling::NativeExtension', double(native_working?: true))
      end

      it { is_expected.to eq [true, nil] }
    end

    context 'when the profiling native library fails to load with a LoadError' do
      before do
        expect(described_class).to receive(:require_relative).with(native_extension_require_relative).and_raise(loaderror)
      end

      let(:loaderror) { LoadError.new('Simulated require failure') }

      it { is_expected.to eq [false, loaderror] }
    end

    context 'when the profiling native library fails to load with a different error' do
      before do
        expect(described_class).to receive(:require_relative).with(native_extension_require_relative).and_raise(error)
      end

      let(:error) { StandardError.new('Simulated require failure') }

      it { is_expected.to eq [false, error] }
    end

    context 'when the profiling native library loads but does not install code correctly' do
      before do
        expect(described_class)
          .to receive(:require_relative)
          .with(native_extension_require_relative)
        stub_const('Datadog::Profiling::NativeExtension', double(native_working?: false))
      end

      it { is_expected.to eq [false, nil] }
    end
  end

  describe '::try_reading_skipped_reason_file' do
    subject(:try_reading_skipped_reason_file) { described_class.send(:try_reading_skipped_reason_file, file_api) }

    let(:file_api) { class_double(File, exist?: exist?, read: read) }
    let(:exist?) { true }
    let(:read) { '' }

    it 'tries to read the skipped_reason.txt file in the native extension folder' do
      expected_path = File.expand_path('../../ext/datadog_profiling_native_extension/skipped_reason.txt', __dir__)

      expect(file_api).to receive(:exist?) do |path|
        expect(File.expand_path(path)).to eq expected_path
      end.and_return(true)

      expect(file_api).to receive(:read) do |path|
        expect(File.expand_path(path)).to eq expected_path
      end.and_return('')

      try_reading_skipped_reason_file
    end

    context 'when file does not exist' do
      let(:exist?) { false }

      it { is_expected.to be nil }
    end

    context 'when file fails to open' do
      let(:exist?) { true }

      before do
        expect(file_api).to receive(:read) { File.open('this-will-fail') }
      end

      it { is_expected.to be nil }
    end

    context 'when file is empty' do
      let(:read) { " \t\n" }

      it { is_expected.to be nil }
    end

    context 'when file exists and has content' do
      let(:read) { 'skipped reason content' }

      it 'returns the content' do
        is_expected.to eq 'skipped reason content'
      end
    end
  end
end
