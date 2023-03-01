# frozen_string_literal: true

module Datadog
  module Profiling
    # Profiling component
    module Component
      def build_profiler(settings, agent_settings, tracer)
        return unless settings.profiling.enabled

        # Workaround for weird dependency direction: the Core::Configuration::Components class currently has a
        # dependency on individual products, in this case the Profiler.
        # (Note "currently": in the future we want to change this so core classes don't depend on specific products)
        #
        # If the current file included a `require 'datadog/profiler'` at its beginning, we would generate circular
        # requires when used from profiling:
        #
        # datadog/profiling
        #     └─requires─> datadog/core
        #                      └─requires─> datadog/core/configuration/components
        #                                       └─requires─> datadog/profiling       # Loop!
        #
        # ...thus in #1998 we removed such a require.
        #
        # On the other hand, if datadog/core is loaded by a different product and no general `require 'ddtrace'` is
        # done, then profiling may not be loaded, and thus to avoid this issue we do a require here (which is a
        # no-op if profiling is already loaded).
        require_relative '../profiling'
        return unless Profiling.supported?

        unless defined?(Profiling::Tasks::Setup)
          # In #1545 a user reported a NameError due to this constant being uninitialized
          # I've documented my suspicion on why that happened in
          # https://github.com/DataDog/dd-trace-rb/issues/1545#issuecomment-856049025
          #
          # > Thanks for the info! It seems to feed into my theory: there's two moments in the code where we check if
          # > profiler is "supported": 1) when loading ddtrace (inside preload) and 2) when starting the profile
          # > after Datadog.configure gets run.
          # > The problem is that the code assumes that both checks 1) and 2) will always reach the same conclusion:
          # > either profiler is supported, or profiler is not supported.
          # > In the problematic case, it looks like in your case check 1 decides that profiler is not
          # > supported => doesn't load it, and then check 2 decides that it is => assumes it is loaded and tries to
          # > start it.
          #
          # I was never able to validate if this was the issue or why exactly .supported? would change its mind BUT
          # just in case it happens again, I've left this check which avoids breaking the user's application AND
          # would instead direct them to report it to us instead, so that we can investigate what's wrong.
          #
          # TODO: As of June 2021, most checks in .supported? are related to the google-protobuf gem; so it's
          # very likely that it was the origin of the issue we saw. Thus, if, as planned we end up moving away from
          # protobuf OR enough time has passed and no users saw the issue again, we can remove this check altogether.
          Datadog.logger.error(
            'Profiling was marked as supported and enabled, but setup task was not loaded properly. ' \
            'Please report this at https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug'
          )

          return
        end

        # Load extensions needed to support some of the Profiling features
        Profiling::Tasks::Setup.new.run

        # NOTE: Please update the Initialization section of ProfilingDevelopment.md with any changes to this method

        if settings.profiling.advanced.force_enable_new_profiler
          print_new_profiler_warnings

          recorder = Datadog::Profiling::StackRecorder.new(
            cpu_time_enabled: RUBY_PLATFORM.include?('linux'), # Only supported on Linux currently
            alloc_samples_enabled: false, # Always disabled for now -- work in progress
          )
          collector = Datadog::Profiling::Collectors::CpuAndWallTimeWorker.new(
            recorder: recorder,
            max_frames: settings.profiling.advanced.max_frames,
            tracer: tracer,
            gc_profiling_enabled: should_enable_gc_profiling?(settings),
            allocation_counting_enabled: settings.profiling.advanced.allocation_counting_enabled,
          )
        else
          trace_identifiers_helper = Profiling::TraceIdentifiers::Helper.new(
            tracer: tracer,
            endpoint_collection_enabled: settings.profiling.advanced.endpoint.collection.enabled
          )

          recorder = build_profiler_old_recorder(settings)
          collector = build_profiler_oldstack_collector(settings, recorder, trace_identifiers_helper)
        end

        exporter = build_profiler_exporter(settings, recorder)
        transport = build_profiler_transport(settings, agent_settings)
        scheduler = Profiling::Scheduler.new(exporter: exporter, transport: transport)

        Profiling::Profiler.new([collector], scheduler)
      end

      private

      def build_profiler_old_recorder(settings)
        Profiling::OldRecorder.new([Profiling::Events::StackSample], settings.profiling.advanced.max_events)
      end

      def build_profiler_exporter(settings, recorder)
        code_provenance_collector =
          (Profiling::Collectors::CodeProvenance.new if settings.profiling.advanced.code_provenance_enabled)

        Profiling::Exporter.new(pprof_recorder: recorder, code_provenance_collector: code_provenance_collector)
      end

      def build_profiler_oldstack_collector(settings, old_recorder, trace_identifiers_helper)
        Profiling::Collectors::OldStack.new(
          old_recorder,
          trace_identifiers_helper: trace_identifiers_helper,
          max_frames: settings.profiling.advanced.max_frames
        )
      end

      def build_profiler_transport(settings, agent_settings)
        settings.profiling.exporter.transport ||
          Profiling::HttpTransport.new(
            agent_settings: agent_settings,
            site: settings.site,
            api_key: settings.api_key,
            upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          )
      end

      def should_enable_gc_profiling?(settings)
        # See comments on the setting definition for more context on why it exists.
        if settings.profiling.advanced.force_enable_gc_profiling
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3')
            Datadog.logger.debug(
              'Profiling time/resources spent in Garbage Collection force enabled. Do not use Ractors in combination ' \
              'with this option as profiles will be incomplete.'
            )
          end

          true
        else
          false
        end
      end

      def print_new_profiler_warnings
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.6')
          Datadog.logger.warn(
            'New Ruby profiler has been force-enabled. This is a beta feature. Please report any issues ' \
            'you run into to Datadog support or via <https://github.com/datadog/dd-trace-rb/issues/new>!'
          )
        else
          # For more details on the issue, see the "BIG Issue" comment on `gvl_owner` function in
          # `private_vm_api_access.c`.
          Datadog.logger.warn(
            'New Ruby profiler has been force-enabled on a legacy Ruby version (< 2.6). This is not recommended in ' \
            'production environments, as due to limitations in Ruby APIs, we suspect it may lead to crashes in very ' \
            'rare situations. Please report any issues you run into to Datadog support or ' \
            'via <https://github.com/datadog/dd-trace-rb/issues/new>!'
          )
        end
      end
    end
  end
end
