require "datadog/profiling/spec_helper"

RSpec.describe Datadog::Profiling::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:logger) { nil }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: logger) }
  let(:profiler_setup_task) { instance_double(Datadog::Profiling::Tasks::Setup) if Datadog::Profiling.supported? }

  before do
    # Make sure these never get run so they doesn't apply our monkey patches to the RSpec process
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
      allow(Datadog::Profiling::Ext::DirMonkeyPatches).to receive(:apply!).and_return(true)
    end
  end

  describe ".build_profiler_component" do
    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

    subject(:build_profiler_component) do
      described_class.build_profiler_component(
        settings: settings,
        agent_settings: agent_settings,
        optional_tracer: tracer
      )
    end

    context "when profiling is not supported" do
      before { allow(Datadog::Profiling).to receive(:supported?).and_return(false) }

      it { is_expected.to eq [nil, {profiling_enabled: false}] }
    end

    context "by default" do
      it "does not build a profiler" do
        is_expected.to eq [nil, {profiling_enabled: false}]
      end
    end

    context "with :enabled false" do
      before do
        settings.profiling.enabled = false
      end

      it "does not build a profiler" do
        is_expected.to eq [nil, {profiling_enabled: false}]
      end
    end

    context "with :enabled true" do
      before do
        skip_if_profiling_not_supported(self)

        settings.profiling.enabled = true
        # Disabled to avoid warnings on Rubies where it's not supported; there's separate specs that test it when enabled
        settings.profiling.advanced.gc_enabled = false
        allow(profiler_setup_task).to receive(:run)
      end

      it "builds a profiler instance" do
        expect(build_profiler_component).to match([instance_of(Datadog::Profiling::Profiler), {profiling_enabled: true}])
      end

      context "when using the new CPU Profiling 2.0 profiler" do
        it "initializes a ThreadContext collector" do
          allow(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new)
          dummy_stack_recorder = instance_double(Datadog::Profiling::StackRecorder, "dummy_stack_recorder")
          allow(Datadog::Profiling::StackRecorder).to receive(:new).and_return(dummy_stack_recorder)

          expect(settings.profiling.advanced).to receive(:max_frames).and_return(:max_frames_config)
          expect(settings.profiling.advanced)
            .to receive(:timeline_enabled).at_least(:once).and_return(:timeline_enabled_config)
          expect(settings.profiling.advanced.endpoint.collection)
            .to receive(:enabled).and_return(:endpoint_collection_enabled_config)
          expect(settings.profiling.advanced).to receive(:waiting_for_gvl_threshold_ns).and_return(:threshold_ns_config)

          expect(Datadog::Profiling::Collectors::ThreadContext).to receive(:new).with(
            recorder: dummy_stack_recorder,
            max_frames: :max_frames_config,
            tracer: tracer,
            endpoint_collection_enabled: :endpoint_collection_enabled_config,
            timeline_enabled: :timeline_enabled_config,
            waiting_for_gvl_threshold_ns: :threshold_ns_config,
            otel_context_enabled: false,
          )

          build_profiler_component
        end

        context "when otel_context_enabled is set to 'both'" do
          before { settings.profiling.advanced.preview_otel_context_enabled = "both" }

          it "initializes a ThreadContext collector with otel_context_enabled: :both" do
            expect(Datadog::Profiling::Collectors::ThreadContext).to receive(:new)
              .with(hash_including(otel_context_enabled: :both))
              .and_call_original

            build_profiler_component
          end
        end

        context "when otel_context_enabled is set to 'only'" do
          before { settings.profiling.advanced.preview_otel_context_enabled = "only" }

          it "initializes a ThreadContext collector with otel_context_enabled: :only" do
            expect(Datadog::Profiling::Collectors::ThreadContext).to receive(:new)
              .with(hash_including(otel_context_enabled: :only))
              .and_call_original

            build_profiler_component
          end
        end

        it "initializes a CpuAndWallTimeWorker collector" do
          expect(described_class).to receive(:no_signals_workaround_enabled?).and_return(:no_signals_result)
          expect(settings.profiling.advanced).to receive(:overhead_target_percentage)
            .and_return(:overhead_target_percentage_config)
          expect(described_class).to receive(:valid_overhead_target)
            .with(:overhead_target_percentage_config).and_return(:overhead_target_percentage_config)
          expect(settings.profiling.advanced)
            .to receive(:allocation_counting_enabled).and_return(:allocation_counting_enabled_config)
          expect(described_class).to receive(:enable_gvl_profiling?).and_return(:gvl_profiling_result)

          expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with(
            gc_profiling_enabled: anything,
            no_signals_workaround_enabled: :no_signals_result,
            thread_context_collector: instance_of(Datadog::Profiling::Collectors::ThreadContext),
            dynamic_sampling_rate_overhead_target_percentage: :overhead_target_percentage_config,
            allocation_profiling_enabled: false,
            allocation_counting_enabled: :allocation_counting_enabled_config,
            gvl_profiling_enabled: :gvl_profiling_result,
          )

          build_profiler_component
        end

        context "when gc_enabled is true" do
          before do
            settings.profiling.advanced.gc_enabled = true
            stub_const("RUBY_VERSION", testing_version)
          end

          ["2.7.0", "3.1.4", "3.2.3", "3.3.0"].each do |fixed_ruby|
            context "on a Ruby version not affected by https://bugs.ruby-lang.org/issues/18464 (#{fixed_ruby})" do
              let(:testing_version) { fixed_ruby }

              it "initializes a CpuAndWallTimeWorker collector with gc_profiling_enabled set to true" do
                expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                  gc_profiling_enabled: true,
                )

                allow(Datadog.logger).to receive(:debug)

                build_profiler_component
              end
            end
          end

          ["3.0.0", "3.1.0", "3.1.3"].each do |broken_ractors_ruby|
            context "on a Ruby version affected by https://bugs.ruby-lang.org/issues/18464 (#{broken_ractors_ruby})" do
              let(:testing_version) { broken_ractors_ruby }

              it "initializes a CpuAndWallTimeWorker collector with gc_profiling_enabled set to false and warns" do
                expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                  gc_profiling_enabled: false,
                )

                expect(Datadog.logger).to receive(:warn).with(/has been disabled/)

                build_profiler_component
              end
            end
          end

          context "on Ruby 3" do
            let(:testing_version) { "3.3.0" }

            it "emits a debug log about Ractors interfering with GC profiling" do
              expect(Datadog.logger)
                .to receive(:debug).with(/using Ractors may result in GC profiling unexpectedly stopping/)

              build_profiler_component
            end
          end
        end

        context "when gc_enabled is false" do
          before { settings.profiling.advanced.gc_enabled = false }

          it "initializes a CpuAndWallTimeWorker collector with gc_profiling_enabled set to false" do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              gc_profiling_enabled: false,
            )

            build_profiler_component
          end
        end

        context "when allocation profiling is enabled" do
          before do
            settings.profiling.allocation_enabled = true
            settings.profiling.advanced.gc_enabled = false # Disable this to avoid any additional warnings coming from it
            stub_const("RUBY_VERSION", testing_version)
          end

          context "on Ruby 2.x" do
            let(:testing_version) { "2.5.0" }

            it "initializes CpuAndWallTimeWorker and StackRecorder with allocation sampling support" do
              expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                allocation_profiling_enabled: true,
              )
              expect(Datadog::Profiling::StackRecorder).to receive(:new)
                .with(hash_including(alloc_samples_enabled: true))
                .and_call_original

              expect(Datadog.logger).to receive(:debug).with(/Enabled allocation profiling/)
              expect(Datadog.logger).to_not receive(:warn)

              build_profiler_component
            end
          end

          ["3.2.0", "3.2.1", "3.2.2"].each do |broken_ruby|
            context "on a Ruby 3 version affected by https://bugs.ruby-lang.org/issues/19482 (#{broken_ruby})" do
              let(:testing_version) { broken_ruby }

              it "initializes a CpuAndWallTimeWorker and StackRecorder with allocation sampling force-disabled and warns" do
                expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                  allocation_profiling_enabled: false,
                )
                expect(Datadog::Profiling::StackRecorder).to receive(:new)
                  .with(hash_including(alloc_samples_enabled: false))
                  .and_call_original

                expect(Datadog.logger).to receive(:warn).with(/forcibly disabled/)
                expect(Datadog.logger).to_not receive(:warn).with(/Ractor/)

                build_profiler_component
              end
            end
          end

          ["3.0.0", "3.1.0", "3.1.3"].each do |broken_ractors_ruby|
            context "on a Ruby 3 version affected by https://bugs.ruby-lang.org/issues/18464 (#{broken_ractors_ruby})" do
              let(:testing_version) { broken_ractors_ruby }

              it "initializes CpuAndWallTimeWorker and StackRecorder with allocation sampling support and warns" do
                expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                  allocation_profiling_enabled: true,
                )
                expect(Datadog::Profiling::StackRecorder).to receive(:new)
                  .with(hash_including(alloc_samples_enabled: true))
                  .and_call_original

                expect(Datadog.logger).to receive(:warn).with(/Ractors.+crashes/)
                expect(Datadog.logger).to receive(:debug).with(/Enabled allocation profiling/)

                build_profiler_component
              end
            end
          end

          ["3.1.4", "3.2.3", "3.3.0"].each do |fixed_ruby|
            context "on a Ruby 3 version where https://bugs.ruby-lang.org/issues/18464 is fixed (#{fixed_ruby})" do
              let(:testing_version) { fixed_ruby }
              it "initializes CpuAndWallTimeWorker and StackRecorder with allocation sampling support and warns" do
                expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
                  allocation_profiling_enabled: true,
                )
                expect(Datadog::Profiling::StackRecorder).to receive(:new)
                  .with(hash_including(alloc_samples_enabled: true))
                  .and_call_original

                expect(Datadog.logger).to receive(:warn).with(/Ractors.+stopping/)
                expect(Datadog.logger).to receive(:debug).with(/Enabled allocation profiling/)

                build_profiler_component
              end
            end
          end
        end

        context "when allocation profiling is disabled" do
          before do
            settings.profiling.allocation_enabled = false
          end

          it "initializes CpuAndWallTimeWorker and StackRecorder without allocation sampling support" do
            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new).with hash_including(
              allocation_profiling_enabled: false,
            )
            expect(Datadog::Profiling::StackRecorder).to receive(:new)
              .with(hash_including(alloc_samples_enabled: false))
              .and_call_original

            build_profiler_component
          end
        end

        context "when heap profiling is enabled" do
          # Universally supported ruby version for allocation profiling by default
          let(:testing_version) { "3.3.0" }

          before do
            settings.profiling.advanced.experimental_heap_enabled = true
            settings.profiling.advanced.gc_enabled = false # Disable this to avoid any additional warnings coming from it
            stub_const("RUBY_VERSION", testing_version)
          end

          context "on a Ruby older than 3.1" do
            let(:testing_version) { "3.0" }

            it "initializes StackRecorder without heap sampling support and warns" do
              expect(Datadog::Profiling::StackRecorder).to receive(:new)
                .with(hash_including(heap_samples_enabled: false, heap_size_enabled: false))
                .and_call_original

              expect(Datadog.logger).to receive(:warn).with(/upgrade to Ruby >= 3.1/)

              build_profiler_component
            end
          end

          context "and allocation profiling disabled" do
            before do
              settings.profiling.allocation_enabled = false
            end

            it "raises an ArgumentError during component initialization" do
              expect { build_profiler_component }.to raise_error(ArgumentError, /requires allocation profiling/)
            end
          end

          context "and allocation profiling enabled and supported" do
            before do
              settings.profiling.allocation_enabled = true
            end

            it "initializes StackRecorder with heap sampling support and warns" do
              expect(Datadog::Profiling::StackRecorder).to receive(:new)
                .with(hash_including(heap_samples_enabled: true, heap_size_enabled: true))
                .and_call_original

              expect(Datadog.logger).to receive(:warn).with(/Ractors.+stopping/)
              expect(Datadog.logger).to receive(:debug).with(/Enabled allocation profiling/)
              expect(Datadog.logger).to receive(:warn).with(/experimental heap profiling/)
              expect(Datadog.logger).to receive(:warn).with(/experimental heap size profiling/)

              build_profiler_component
            end

            context "but heap size profiling is disabled" do
              before do
                settings.profiling.advanced.experimental_heap_size_enabled = false
              end

              it "initializes StackRecorder without heap size profiling support" do
                expect(Datadog::Profiling::StackRecorder).to receive(:new)
                  .with(hash_including(heap_samples_enabled: true, heap_size_enabled: false))
                  .and_call_original

                expect(Datadog.logger).to receive(:debug).with(/Enabled allocation profiling/)
                expect(Datadog.logger).to receive(:warn).with(/experimental heap profiling/)
                expect(Datadog.logger).not_to receive(:warn).with(/experimental heap size profiling/)

                build_profiler_component
              end
            end
          end
        end

        context "when heap profiling is disabled" do
          before do
            settings.profiling.advanced.experimental_heap_enabled = false
          end

          it "initializes StackRecorder without heap sampling support" do
            expect(Datadog::Profiling::StackRecorder).to receive(:new)
              .with(hash_including(heap_samples_enabled: false, heap_size_enabled: false))
              .and_call_original

            build_profiler_component
          end
        end

        context "when timeline is enabled" do
          before { settings.profiling.advanced.timeline_enabled = true }

          it "sets up the StackRecorder with timeline_enabled: true" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(timeline_enabled: true)).and_call_original

            build_profiler_component
          end
        end

        context "when timeline is disabled" do
          before { settings.profiling.advanced.timeline_enabled = false }

          it "sets up the StackRecorder with timeline_enabled: false" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(timeline_enabled: false)).and_call_original

            build_profiler_component
          end
        end

        context "when heap_clean_after_gc_enabled is enabled" do
          before { settings.profiling.advanced.heap_clean_after_gc_enabled = true }

          it "sets up the StackRecorder with heap_clean_after_gc_enabled: true" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(heap_clean_after_gc_enabled: true)).and_call_original

            build_profiler_component
          end
        end

        context "when heap_clean_after_gc_enabled is disabled" do
          before { settings.profiling.advanced.heap_clean_after_gc_enabled = false }

          it "sets up the StackRecorder with heap_clean_after_gc_enabled: false" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(heap_clean_after_gc_enabled: false)).and_call_original

            build_profiler_component
          end
        end

        it "sets up the Profiler with the CpuAndWallTimeWorker collector" do
          expect(Datadog::Profiling::Profiler).to receive(:new).with(
            worker: instance_of(Datadog::Profiling::Collectors::CpuAndWallTimeWorker),
            scheduler: anything
          )

          build_profiler_component
        end

        it "sets up the Exporter with the StackRecorder" do
          expect(Datadog::Profiling::Exporter)
            .to receive(:new).with(hash_including(pprof_recorder: instance_of(Datadog::Profiling::StackRecorder)))

          build_profiler_component
        end

        it "sets up the Exporter internal_metadata with relevant settings" do
          allow(Datadog::Profiling::Collectors::ThreadContext).to receive(:new)
          allow(Datadog::Profiling::Collectors::CpuAndWallTimeWorker).to receive(:new)
          allow(Datadog::Profiling::StackRecorder).to receive(:new)

          expect(described_class).to receive(:no_signals_workaround_enabled?).and_return(:no_signals_result)
          expect(settings.profiling.advanced).to receive(:timeline_enabled).at_least(:once).and_return(:timeline_result)
          expect(settings.profiling.advanced).to receive(:experimental_heap_sample_rate).and_return(456)
          expect(Datadog::Profiling::Exporter).to receive(:new).with(
            hash_including(
              internal_metadata: {
                no_signals_workaround_enabled: :no_signals_result,
                timeline_enabled: :timeline_result,
                heap_sample_every: 456,
              }
            )
          )

          build_profiler_component
        end

        context "when on Linux" do
          before { stub_const("RUBY_PLATFORM", "some-linux-based-platform") }

          it "sets up the StackRecorder with cpu_time_enabled: true" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(cpu_time_enabled: true)).and_call_original

            build_profiler_component
          end
        end

        context "when not on Linux" do
          before { stub_const("RUBY_PLATFORM", "some-other-os") }

          it "sets up the StackRecorder with cpu_time_enabled: false" do
            expect(Datadog::Profiling::StackRecorder)
              .to receive(:new).with(hash_including(cpu_time_enabled: false)).and_call_original

            build_profiler_component
          end
        end
      end

      it "runs the setup task to set up any needed extensions for profiling" do
        expect(profiler_setup_task).to receive(:run)

        build_profiler_component
      end

      it "builds an HttpTransport with the current settings" do
        expect(Datadog::Profiling::HttpTransport).to receive(:new).with(
          agent_settings: agent_settings,
          site: settings.site,
          api_key: settings.api_key,
          upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
        )

        build_profiler_component
      end

      it "creates a scheduler with an HttpTransport" do
        expect(Datadog::Profiling::Scheduler).to receive(:new) do |transport:, **_|
          expect(transport).to be_a_kind_of(Datadog::Profiling::HttpTransport)
        end

        build_profiler_component
      end

      context "when upload_period_seconds is below 60 seconds" do
        before { settings.profiling.advanced.upload_period_seconds = 59 }

        it "ignores this setting and creates a scheduler with an interval of 60 seconds" do
          expect(Datadog::Profiling::Scheduler).to receive(:new).with(a_hash_including(interval: 60))

          build_profiler_component
        end
      end

      context "when upload_period_seconds is over 60 seconds" do
        before { settings.profiling.advanced.upload_period_seconds = 61 }

        it "creates a scheduler with the given interval" do
          expect(Datadog::Profiling::Scheduler).to receive(:new).with(a_hash_including(interval: 61))

          build_profiler_component
        end
      end

      it "initializes the exporter with a code provenance collector" do
        expect(Datadog::Profiling::Exporter).to receive(:new) do |code_provenance_collector:, **_|
          expect(code_provenance_collector).to be_a_kind_of(Datadog::Profiling::Collectors::CodeProvenance)
        end

        build_profiler_component
      end

      context "when code provenance is disabled" do
        before { settings.profiling.advanced.code_provenance_enabled = false }

        it "initializes the exporter with a nil code provenance collector" do
          expect(Datadog::Profiling::Exporter).to receive(:new) do |code_provenance_collector:, **_|
            expect(code_provenance_collector).to be nil
          end

          build_profiler_component
        end
      end

      context "when a custom transport is provided" do
        let(:custom_transport) { double("Custom transport") }

        before do
          settings.profiling.exporter.transport = custom_transport
        end

        it "does not initialize an HttpTransport" do
          expect(Datadog::Profiling::HttpTransport).to_not receive(:new)

          build_profiler_component
        end

        it "sets up the scheduler to use the custom transport" do
          expect(Datadog::Profiling::Scheduler).to receive(:new) do |transport:, **_|
            expect(transport).to be custom_transport
          end

          build_profiler_component
        end
      end

      describe "dir interruption workaround" do
        let(:no_signals_workaround_enabled) { false }

        before do
          allow(described_class).to receive(:no_signals_workaround_enabled?).and_return(no_signals_workaround_enabled)
        end

        context "on Ruby >= 3.4" do
          before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION < "3.4." }

          it "is never applied" do
            expect(Datadog::Profiling::Ext::DirMonkeyPatches).to_not receive(:apply!)

            build_profiler_component
          end
        end

        context "on Ruby < 3.4" do
          before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION >= "3.4." }

          it "is applied by default" do
            expect(Datadog::Profiling::Ext::DirMonkeyPatches).to receive(:apply!)

            build_profiler_component
          end
        end

        context "when the no signals workaround is enabled" do
          let(:no_signals_workaround_enabled) { true }

          it "is not applied" do
            expect(Datadog::Profiling::Ext::DirMonkeyPatches).to_not receive(:apply!)

            build_profiler_component
          end
        end

        context "when the dir interruption workaround is disabled via configuration" do
          before { settings.profiling.advanced.dir_interruption_workaround_enabled = false }

          it "is not applied" do
            expect(Datadog::Profiling::Ext::DirMonkeyPatches).to_not receive(:apply!)

            build_profiler_component
          end
        end
      end

      context "when GVL profiling is requested" do
        before do
          settings.profiling.advanced.preview_gvl_enabled = true
          # This triggers a warning in some Rubies so it's easier for testing to disable it
          settings.profiling.advanced.gc_enabled = false
        end

        context "on Ruby < 3.2" do
          before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION >= "3.2." }

          it "does not enable GVL profiling" do
            allow(Datadog.logger).to receive(:warn)

            expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
              .to receive(:new).with(hash_including(gvl_profiling_enabled: false))

            build_profiler_component
          end

          it "logs a warning" do
            expect(Datadog.logger).to receive(:warn).with(/GVL profiling is currently not supported/)

            build_profiler_component
          end
        end

        context "on Ruby >= 3.2" do
          before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION < "3.2." }

          context "when timeline is enabled" do
            before { settings.profiling.advanced.timeline_enabled = true }

            it "enables GVL profiling" do
              expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
                .to receive(:new).with(hash_including(gvl_profiling_enabled: true))

              build_profiler_component
            end
          end

          context "when timeline is disabled" do
            before { settings.profiling.advanced.timeline_enabled = false }

            it "does not enable GVL profiling" do
              expect(Datadog::Profiling::Collectors::CpuAndWallTimeWorker)
                .to receive(:new).with(hash_including(gvl_profiling_enabled: false))

              build_profiler_component
            end
          end
        end
      end
    end
  end

  describe ".valid_overhead_target" do
    subject(:valid_overhead_target) { described_class.send(:valid_overhead_target, overhead_target_percentage) }

    [0, 20.1].each do |invalid_value|
      let(:overhead_target_percentage) { invalid_value }

      context "when overhead_target_percentage is invalid value (#{invalid_value})" do
        it "logs an error" do
          expect(Datadog.logger).to receive(:error).with(
            /Ignoring invalid value for profiling overhead_target_percentage/
          )

          valid_overhead_target
        end

        it "falls back to the default value" do
          allow(Datadog.logger).to receive(:error)

          expect(valid_overhead_target).to eq 2.0
        end
      end
    end

    context "when overhead_target_percentage is valid" do
      let(:overhead_target_percentage) { 1.5 }

      it "returns the value" do
        expect(valid_overhead_target).to eq 1.5
      end
    end
  end

  describe ".no_signals_workaround_enabled?" do
    subject(:no_signals_workaround_enabled?) { described_class.send(:no_signals_workaround_enabled?, settings) }

    before { skip_if_profiling_not_supported(self) }

    context "when no_signals_workaround_enabled is false" do
      before do
        settings.profiling.advanced.no_signals_workaround_enabled = false
        allow(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to be false }

      context "on Ruby 2.5 and below" do
        before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION >= "2.6." }

        it "logs a warning message mentioning that this is is not recommended" do
          expect(Datadog.logger).to receive(:warn).with(
            /workaround has been disabled via configuration.*This is not recommended/
          )

          no_signals_workaround_enabled?
        end
      end

      context "on Ruby 2.6 and above" do
        before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION < "2.6." }

        it "logs a warning message mentioning that the no signals mode has been disabled" do
          expect(Datadog.logger).to receive(:warn).with('Profiling "no signals" workaround disabled via configuration')

          no_signals_workaround_enabled?
        end
      end
    end

    context "when no_signals_workaround_enabled is true" do
      before do
        settings.profiling.advanced.no_signals_workaround_enabled = true
        allow(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to be true }

      it "logs a warning message mentioning that this setting is active" do
        expect(Datadog.logger).to receive(:warn).with(/Profiling "no signals" workaround enabled via configuration/)

        no_signals_workaround_enabled?
      end
    end

    shared_examples "no_signals_workaround_enabled :auto behavior" do
      context "on Ruby 2.5 and below" do
        before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION >= "2.6." }

        it { is_expected.to be true }
      end

      context "on Ruby 2.6 and above" do
        before { skip "Behavior does not apply to current Ruby version" if RUBY_VERSION < "2.6." }

        context "when mysql2 gem is available" do
          include_context("loaded gems", mysql2: Gem::Version.new("0.5.5"), rugged: nil)

          before do
            allow(Datadog.logger).to receive(:warn)
            allow(Datadog.logger).to receive(:debug)
          end

          context "when skip_mysql2_check is enabled" do
            before { settings.profiling.advanced.skip_mysql2_check = true }

            it { is_expected.to be true }

            it "logs a warning message mentioning that the no signals workaround is going to be used" do
              expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

              no_signals_workaround_enabled?
            end
          end

          context "when there is an issue requiring mysql2" do
            before { allow(described_class).to receive(:require).and_raise(LoadError.new("Simulated require failure")) }

            it { is_expected.to be true }

            it "logs that probing mysql2 failed" do
              expect(Datadog.logger).to receive(:warn).with(/Failed to probe `mysql2` gem information/)

              no_signals_workaround_enabled?
            end
          end

          context "when mysql2 is required successfully" do
            before { allow(described_class).to receive(:require).with("mysql2") }

            it "logs a debug message stating mysql2 will be required" do
              expect(Datadog.logger).to receive(:debug).with(/Requiring `mysql2` to check/)

              no_signals_workaround_enabled?
            end

            context "when mysql2 gem does not provide the info method" do
              before do
                stub_const("Mysql2::Client", double("Fake Mysql2::Client"))
              end

              it { is_expected.to be true }
            end

            context "when an error is raised while probing the mysql2 gem" do
              before do
                fake_client = double("Fake Mysql2::Client")
                stub_const("Mysql2::Client", fake_client)
                expect(fake_client).to receive(:info).and_raise(ArgumentError.new("Simulated call failure"))
              end

              it { is_expected.to be true }

              it "logs a warning including the error details" do
                expect(Datadog.logger).to receive(:warn).with(/Failed to probe `mysql2` gem information/)

                no_signals_workaround_enabled?
              end
            end

            # See comments on looks_like_mariadb? for details on how this matching works
            context "when mysql2 gem is linked to mariadb's version of libmysqlclient" do
              before do
                fake_client = double("Fake Mysql2::Client")
                stub_const("Mysql2::Client", fake_client)
                expect(fake_client).to receive(:info).and_return({version: "4.9.99", header_version: "10.0.0"})
              end

              it { is_expected.to be false }

              it "does not log any warning message" do
                expect(Datadog.logger).to_not receive(:warn)

                no_signals_workaround_enabled?
              end
            end

            context "when mysql2 gem is using a version of libmysqlclient < 8.0.0" do
              before do
                fake_client = double("Fake Mysql2::Client")
                stub_const("Mysql2::Client", fake_client)
                expect(fake_client).to receive(:info).and_return({version: "7.9.9"})
              end

              it { is_expected.to be true }

              it "logs a warning message mentioning that the no signals workaround is going to be used" do
                expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

                no_signals_workaround_enabled?
              end
            end

            context "when mysql2 gem is using a version of libmysqlclient >= 8.0.0" do
              before do
                fake_client = double("Fake Mysql2::Client")
                stub_const("Mysql2::Client", fake_client)
                expect(fake_client).to receive(:info).and_return({version: "8.0.0"})
              end

              it { is_expected.to be false }

              it "does not log any warning message" do
                expect(Datadog.logger).to_not receive(:warn)

                no_signals_workaround_enabled?
              end
            end

            context "when mysql2-aurora gem is loaded and libmysqlclient < 8.0.0" do
              before do
                fake_original_client = double("Fake original Mysql2::Client")
                stub_const("Mysql2::Aurora::ORIGINAL_CLIENT_CLASS", fake_original_client)
                expect(fake_original_client).to receive(:info).and_return({version: "7.9.9"})

                client_replaced_by_aurora = double("Fake Aurora Mysql2::Client")
                stub_const("Mysql2::Client", client_replaced_by_aurora)
              end

              it { is_expected.to be true }
            end

            context "when mysql2-aurora gem is loaded and libmysqlclient >= 8.0.0" do
              before do
                fake_original_client = double("Fake original Mysql2::Client")
                stub_const("Mysql2::Aurora::ORIGINAL_CLIENT_CLASS", fake_original_client)
                expect(fake_original_client).to receive(:info).and_return({version: "8.0.0"})

                client_replaced_by_aurora = double("Fake Aurora Mysql2::Client")
                stub_const("Mysql2::Client", client_replaced_by_aurora)
              end

              it { is_expected.to be false }
            end
          end
        end

        context "when rugged gem is available" do
          include_context("loaded gems", rugged: Gem::Version.new("1.6.3"), mysql2: nil)

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to be true }

          it "logs a warning message mentioning that the no signals workaround is going to be used" do
            expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

            no_signals_workaround_enabled?
          end
        end

        context "when running inside the passenger web server, even when gem is not available" do
          include_context("loaded gems", passenger: nil, rugged: nil, mysql2: nil)

          before do
            stub_const("::PhusionPassenger", Module.new)
            allow(Datadog.logger).to receive(:warn)
          end

          it { is_expected.to be true }

          it "logs a warning message mentioning that the no signals workaround is going to be used" do
            expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

            no_signals_workaround_enabled?
          end
        end

        context "when passenger gem is available" do
          context "on passenger >= 6.0.19" do
            include_context("loaded gems", passenger: Gem::Version.new("6.0.19"), rugged: nil, mysql2: nil)

            it { is_expected.to be false }
          end

          context "on passenger < 6.0.19" do
            include_context("loaded gems", passenger: Gem::Version.new("6.0.18"), rugged: nil, mysql2: nil)

            before { allow(Datadog.logger).to receive(:warn) }

            it { is_expected.to be true }

            it "logs a warning message mentioning that the no signals workaround is going to be used" do
              expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

              no_signals_workaround_enabled?
            end
          end
        end

        context "when passenger gem is not available, but PhusionPassenger::VERSION_STRING is available" do
          context "on passenger >= 6.0.19" do
            before { stub_const("PhusionPassenger::VERSION_STRING", "6.0.19") }

            it { is_expected.to be false }
          end

          context "on passenger < 6.0.19" do
            before do
              stub_const("PhusionPassenger::VERSION_STRING", "6.0.18")
              allow(Datadog.logger).to receive(:warn)
            end

            it { is_expected.to be true }

            it "logs a warning message mentioning that the no signals workaround is going to be used" do
              expect(Datadog.logger).to receive(:warn).with(/Enabling the profiling "no signals" workaround/)

              no_signals_workaround_enabled?
            end
          end
        end

        context "when mysql2 / rugged gems + passenger are not available" do
          include_context("loaded gems", passenger: nil, mysql2: nil, rugged: nil)

          it { is_expected.to be false }
        end
      end
    end

    context "when no_signals_workaround_enabled is :auto" do
      before { settings.profiling.advanced.no_signals_workaround_enabled = :auto }

      include_examples "no_signals_workaround_enabled :auto behavior"
    end

    context "when no_signals_workaround_enabled is an invalid value" do
      before do
        settings.profiling.advanced.no_signals_workaround_enabled = "invalid value"
        allow(Datadog.logger).to receive(:error)
      end

      it "logs an error message mentioning that the invalid value will be ignored" do
        expect(Datadog.logger).to receive(:error).with(/Ignoring invalid value/)

        no_signals_workaround_enabled?
      end

      include_examples "no_signals_workaround_enabled :auto behavior"
    end
  end
end
