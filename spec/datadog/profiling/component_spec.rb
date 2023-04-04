require 'datadog/profiling/spec_helper'

RSpec.describe Datadog::Profiling::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }
  let(:profiler_setup_task) { instance_double(Datadog::Profiling::Tasks::Setup) if Datadog::Profiling.supported? }

  before do
    # Ensure the real task never gets run (so it doesn't apply our thread patches and other extensions to our test env)
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
    end
  end

  describe '.build_profiler_component' do
    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

    subject(:build_profiler_component) do
      described_class.build_profiler_component(settings: settings, agent_settings: agent_settings, optional_tracer: tracer)
    end

    context 'when profiling is not supported' do
      before { allow(Datadog::Profiling).to receive(:supported?).and_return(false) }

      it { is_expected.to be nil }
    end

    context 'by default' do
      it 'does not build a profiler' do
        is_expected.to be nil
      end
    end

    context 'with :enabled false' do
      before do
        settings.profiling.enabled = false
      end

      it 'does not build a profiler' do
        is_expected.to be nil
      end
    end

    context 'with :enabled true' do
      before do
        skip_if_profiling_not_supported(self)

        settings.profiling.enabled = true
        allow(profiler_setup_task).to receive(:run)
      end

      context 'when using the legacy profiler' do
        before { expect(described_class).to receive(:enable_new_profiler?).with(settings).and_return(false) }

        it 'sets up the Profiler with the OldStack collector' do
          expect(Datadog::Profiling::Profiler).to receive(:new).with(
            [instance_of(Datadog::Profiling::Collectors::OldStack)],
            anything,
          )

          build_profiler_component
        end

        it 'initializes the OldStack collector with the max_frames setting' do
          expect(Datadog::Profiling::Collectors::OldStack).to receive(:new).with(
            instance_of(Datadog::Profiling::OldRecorder),
            hash_including(max_frames: settings.profiling.advanced.max_frames),
          )

          build_profiler_component
        end

        it 'initializes the OldRecorder with the correct event classes and max_events setting' do
          expect(Datadog::Profiling::OldRecorder)
            .to receive(:new)
            .with([Datadog::Profiling::Events::StackSample], settings.profiling.advanced.max_events)
            .and_call_original

          build_profiler_component
        end

        it 'sets up the Exporter with the OldRecorder' do
          expect(Datadog::Profiling::Exporter)
            .to receive(:new).with(hash_including(pprof_recorder: instance_of(Datadog::Profiling::OldRecorder)))

          build_profiler_component
        end

        [true, false].each do |value|
          context "when endpoint_collection_enabled is #{value}" do
            before { settings.profiling.advanced.endpoint.collection.enabled = value }

            it "initializes the TraceIdentifiers::Helper with endpoint_collection_enabled: #{value}" do
              expect(Datadog::Profiling::TraceIdentifiers::Helper)
                .to receive(:new).with(tracer: tracer, endpoint_collection_enabled: value)

              build_profiler_component
            end
          end
        end
      end

      context 'when using the new CPU Profiling 2.0 profiler' do
        before do
          expect(described_class).to receive(:enable_new_profiler?).with(settings).and_return(true)
          # Silence warning spam about using the new profiler on legacy Rubies
          allow(Datadog.logger).to receive(:warn) if RUBY_VERSION < '2.6.'
        end

        it 'does not initialize the OldStack collector' do
          expect(Datadog::Profiling::Collectors::OldStack).to_not receive(:new)

          build_profiler_component
        end

        it 'does not initialize the OldRecorder' do
          expect(Datadog::Profiling::OldRecorder).to_not receive(:new)

          build_profiler_component
        end

        it 'initializes a CpuAndWallTimeWorker collector' do
          expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with(
            recorder: instance_of(Datadog::Profiling::StackRecorder),
            max_frames: settings.profiling.advanced.max_frames,
            tracer: tracer,
            endpoint_collection_enabled: anything,
            gc_profiling_enabled: anything,
            allocation_counting_enabled: anything,
          )

          build_profiler_component
        end

        context 'on Ruby 2.5 and below' do
          before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION >= '2.6.' }

          it 'logs a warning message mentioning that profiler has been force-enabled AND that it may cause issues' do
            expect(Datadog.logger).to receive(:warn).with(
              /The new CPU Profiling 2.0 profiler has been force-enabled on a legacy Ruby version/
            )

            build_profiler_component
          end
        end

        it 'initializes a CpuAndWallTimeWorker collector with gc_profiling_enabled set to false' do
          expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
            gc_profiling_enabled: false,
          )

          build_profiler_component
        end

        context 'when force_enable_gc_profiling is enabled' do
          before do
            settings.profiling.advanced.force_enable_gc_profiling = true

            allow(Datadog.logger).to receive(:debug)
          end

          it 'initializes a CpuAndWallTimeWorker collector with gc_profiling_enabled set to true' do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              gc_profiling_enabled: true,
            )

            build_profiler_component
          end

          context 'on Ruby 3.x' do
            before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3.0' }

            it 'logs a debug message' do
              expect(Datadog.logger).to receive(:debug).with(/Garbage Collection force enabled/)

              build_profiler_component
            end
          end
        end

        context 'when allocation_counting_enabled is enabled' do
          before do
            settings.profiling.advanced.allocation_counting_enabled = true
          end

          it 'initializes a CpuAndWallTimeWorker collector with allocation_counting_enabled set to true' do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              allocation_counting_enabled: true,
            )

            build_profiler_component
          end
        end

        context 'when allocation_counting_enabled is disabled' do
          before do
            settings.profiling.advanced.allocation_counting_enabled = false
          end

          it 'initializes a CpuAndWallTimeWorker collector with allocation_counting_enabled set to false' do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              allocation_counting_enabled: false,
            )

            build_profiler_component
          end
        end

        it 'initializes a CpuAndWallTimeWorker collector with endpoint_collection_enabled set to true' do
          expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
            endpoint_collection_enabled: true,
          )

          build_profiler_component
        end

        context 'when endpoint_collection_enabled is disabled' do
          before do
            settings.profiling.advanced.endpoint.collection.enabled = false
          end

          it 'initializes a CpuAndWallTimeWorker collector with endpoint_collection_enabled set to false' do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              endpoint_collection_enabled: false,
            )

            build_profiler_component
          end
        end

        it 'sets up the Profiler with the CpuAndWallTimeWorker collector' do
          expect(Datadog::Profiling::Profiler).to receive(:new).with(
            [instance_of(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)],
            anything,
          )

          build_profiler_component
        end

        it 'sets up the Exporter with the StackRecorder' do
          expect(Datadog::Profiling::Exporter)
            .to receive(:new).with(hash_including(pprof_recorder: instance_of(Datadog::Profiling::StackRecorder)))

          build_profiler_component
        end

        it 'sets up the StackRecorder with alloc_samples_enabled: false' do
          expect(Datadog::Profiling::StackRecorder)
            .to receive(:new).with(hash_including(alloc_samples_enabled: false)).and_call_original

          build_profiler_component
        end

        context 'when on Linux' do
          before { stub_const('RUBY_PLATFORM', 'some-linux-based-platform') }

          it 'sets up the StackRecorder with cpu_time_enabled: true' do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(cpu_time_enabled: true)).and_call_original

            build_profiler_component
          end
        end

        context 'when not on Linux' do
          before { stub_const('RUBY_PLATFORM', 'some-other-os') }

          it 'sets up the StackRecorder with cpu_time_enabled: false' do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(cpu_time_enabled: false)).and_call_original

            build_profiler_component
          end
        end
      end

      it 'runs the setup task to set up any needed extensions for profiling' do
        expect(profiler_setup_task).to receive(:run)

        build_profiler_component
      end

      it 'builds an HttpTransport with the current settings' do
        expect(Datadog::Profiling::HttpTransport).to receive(:new).with(
          agent_settings: agent_settings,
          site: settings.site,
          api_key: settings.api_key,
          upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
        )

        build_profiler_component
      end

      it 'creates a scheduler with an HttpTransport' do
        expect(Datadog::Profiling::Scheduler).to receive(:new) do |transport:, **_|
          expect(transport).to be_a_kind_of(Datadog::Profiling::HttpTransport)
        end

        build_profiler_component
      end

      it 'initializes the exporter with a code provenance collector' do
        expect(Datadog::Profiling::Exporter).to receive(:new) do |code_provenance_collector:, **_|
          expect(code_provenance_collector).to be_a_kind_of(Datadog::Profiling::Collectors::CodeProvenance)
        end

        build_profiler_component
      end

      context 'when code provenance is disabled' do
        before { settings.profiling.advanced.code_provenance_enabled = false }

        it 'initializes the exporter with a nil code provenance collector' do
          expect(Datadog::Profiling::Exporter).to receive(:new) do |code_provenance_collector:, **_|
            expect(code_provenance_collector).to be nil
          end

          build_profiler_component
        end
      end

      context 'when a custom transport is provided' do
        let(:custom_transport) { double('Custom transport') }

        before do
          settings.profiling.exporter.transport = custom_transport
        end

        it 'does not initialize an HttpTransport' do
          expect(Datadog::Profiling::HttpTransport).to_not receive(:new)

          build_profiler_component
        end

        it 'sets up the scheduler to use the custom transport' do
          expect(Datadog::Profiling::Scheduler).to receive(:new) do |transport:, **_|
            expect(transport).to be custom_transport
          end

          build_profiler_component
        end
      end
    end
  end

  describe '.enable_new_profiler?' do
    subject(:enable_new_profiler?) { described_class.send(:enable_new_profiler?, settings) }

    before { skip_if_profiling_not_supported(self) }

    context 'when force_enable_legacy_profiler is enabled' do
      before do
        settings.profiling.advanced.force_enable_legacy_profiler = true

        allow(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to be false }

      it 'logs a warning message mentioning that the legacy profiler was enabled' do
        expect(Datadog.logger).to receive(:warn).with(/Legacy profiler has been force-enabled/)

        enable_new_profiler?
      end
    end

    context 'when force_enable_legacy_profiler is not enabled' do
      before { settings.profiling.advanced.force_enable_legacy_profiler = false }

      context 'on Ruby 2.5 and below' do
        before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION >= '2.6.' }

        it { is_expected.to be false }

        context 'when force_enable_new_profiler is enabled' do
          before { settings.profiling.advanced.force_enable_new_profiler = true }

          it { is_expected.to be true }
        end
      end

      context 'on Ruby 2.6 and above' do
        before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '2.6.' }

        context 'when mysql2 gem is available' do
          include_context 'loaded gems', :mysql2 => Gem::Version.new('0.5.5')

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to be false }

          it 'logs a warning message mentioning that the legacy profiler is going to be used' do
            expect(Datadog.logger).to receive(:warn).with(/Falling back to legacy profiler/)

            enable_new_profiler?
          end

          context 'when force_enable_new_profiler is enabled' do
            before { settings.profiling.advanced.force_enable_new_profiler = true }

            it { is_expected.to be true }
          end
        end

        context 'when rugged gem is available' do
          include_context 'loaded gems', :rugged => Gem::Version.new('1.6.3')

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to be false }

          it 'logs a warning message mentioning that the legacy profiler is going to be used' do
            expect(Datadog.logger).to receive(:warn).with(/Falling back to legacy profiler/)

            enable_new_profiler?
          end

          context 'when force_enable_new_profiler is enabled' do
            before { settings.profiling.advanced.force_enable_new_profiler = true }

            it { is_expected.to be true }
          end
        end

        context 'when mysql2 / rugged gem are not available' do
          include_context('loaded gems', mysql2: nil, rugged: nil)

          it { is_expected.to be true }
        end
      end
    end
  end
end
