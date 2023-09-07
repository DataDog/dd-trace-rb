# frozen_string_literal: true

module Datadog
  module Profiling
    # Responsible for wiring up the Profiler for execution
    module Component
      # Passing in a `nil` tracer is supported and will disable the following profiling features:
      # * Code Hotspots panel in the trace viewer, as well as scoping a profile down to a span
      # * Endpoint aggregation in the profiler UX, including normalization (resource per endpoint call)
      def self.build_profiler_component(settings:, agent_settings:, optional_tracer:) # rubocop:disable Metrics/MethodLength
        require_relative '../profiling/diagnostics/environment_logger'

        Profiling::Diagnostics::EnvironmentLogger.collect_and_log!

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

        no_signals_workaround_enabled = false
        timeline_enabled = false

        if enable_new_profiler?(settings)
          no_signals_workaround_enabled = no_signals_workaround_enabled?(settings)
          timeline_enabled = settings.profiling.advanced.experimental_timeline_enabled

          recorder = Datadog::Profiling::StackRecorder.new(
            cpu_time_enabled: RUBY_PLATFORM.include?('linux'), # Only supported on Linux currently
            alloc_samples_enabled: false, # Always disabled for now -- work in progress
          )
          thread_context_collector = Datadog::Profiling::Collectors::ThreadContext.new(
            recorder: recorder,
            max_frames: settings.profiling.advanced.max_frames,
            tracer: optional_tracer,
            endpoint_collection_enabled: settings.profiling.advanced.endpoint.collection.enabled,
            timeline_enabled: timeline_enabled,
          )
          collector = Datadog::Profiling::Collectors::CpuAndWallTimeWorker.new(
            gc_profiling_enabled: enable_gc_profiling?(settings),
            allocation_counting_enabled: settings.profiling.advanced.allocation_counting_enabled,
            no_signals_workaround_enabled: no_signals_workaround_enabled,
            thread_context_collector: thread_context_collector,
            allocation_sample_every: 0,
          )
        else
          load_pprof_support

          recorder = build_profiler_old_recorder(settings)
          collector = build_profiler_oldstack_collector(settings, recorder, optional_tracer)
        end

        internal_metadata = {
          no_signals_workaround_enabled: no_signals_workaround_enabled,
          timeline_enabled: timeline_enabled,
        }.freeze

        exporter = build_profiler_exporter(settings, recorder, internal_metadata: internal_metadata)
        transport = build_profiler_transport(settings, agent_settings)
        scheduler = Profiling::Scheduler.new(exporter: exporter, transport: transport)

        Profiling::Profiler.new([collector], scheduler)
      end

      private_class_method def self.build_profiler_old_recorder(settings)
        Profiling::OldRecorder.new([Profiling::Events::StackSample], settings.profiling.advanced.max_events)
      end

      private_class_method def self.build_profiler_exporter(settings, recorder, internal_metadata:)
        code_provenance_collector =
          (Profiling::Collectors::CodeProvenance.new if settings.profiling.advanced.code_provenance_enabled)

        Profiling::Exporter.new(
          pprof_recorder: recorder,
          code_provenance_collector: code_provenance_collector,
          internal_metadata: internal_metadata,
        )
      end

      private_class_method def self.build_profiler_oldstack_collector(settings, old_recorder, tracer)
        trace_identifiers_helper = Profiling::TraceIdentifiers::Helper.new(
          tracer: tracer,
          endpoint_collection_enabled: settings.profiling.advanced.endpoint.collection.enabled
        )

        Profiling::Collectors::OldStack.new(
          old_recorder,
          trace_identifiers_helper: trace_identifiers_helper,
          max_frames: settings.profiling.advanced.max_frames
        )
      end

      private_class_method def self.build_profiler_transport(settings, agent_settings)
        settings.profiling.exporter.transport ||
          Profiling::HttpTransport.new(
            agent_settings: agent_settings,
            site: settings.site,
            api_key: settings.api_key,
            upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
          )
      end

      private_class_method def self.enable_gc_profiling?(settings)
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

      private_class_method def self.enable_new_profiler?(settings)
        if settings.profiling.advanced.force_enable_legacy_profiler
          Datadog.logger.warn(
            'Legacy profiler has been force-enabled via configuration. Do not use unless instructed to by support.'
          )
          return false
        end

        true
      end

      private_class_method def self.no_signals_workaround_enabled?(settings) # rubocop:disable Metrics/MethodLength
        setting_value = settings.profiling.advanced.no_signals_workaround_enabled
        legacy_ruby_that_should_use_workaround = RUBY_VERSION.start_with?('2.3.', '2.4.', '2.5.')

        unless [true, false, :auto].include?(setting_value)
          Datadog.logger.error(
            "Ignoring invalid value for profiling no_signals_workaround_enabled setting: #{setting_value.inspect}. " \
            'Valid options are `true`, `false` or (default) `:auto`.'
          )

          setting_value = :auto
        end

        if setting_value == false
          if legacy_ruby_that_should_use_workaround
            Datadog.logger.warn(
              'The profiling "no signals" workaround has been disabled via configuration on a legacy Ruby version ' \
              '(< 2.6). This is not recommended ' \
              'in production environments, as due to limitations in Ruby APIs, we suspect it may lead to crashes ' \
              'in very rare situations. Please report any issues you run into to Datadog support or ' \
              'via <https://github.com/datadog/dd-trace-rb/issues/new>!'
            )
          else
            Datadog.logger.warn('Profiling "no signals" workaround disabled via configuration')
          end

          return false
        end

        if setting_value == true
          Datadog.logger.warn(
            'Profiling "no signals" workaround enabled via configuration. Profiling data will have lower quality.'
          )

          return true
        end

        # Setting is in auto mode. Let's probe to see if we should enable it:

        # We don't warn users in this situation because "upgrade your Ruby" is not a great warning
        return true if legacy_ruby_that_should_use_workaround

        if Gem.loaded_specs['mysql2'] && incompatible_libmysqlclient_version?(settings)
          Datadog.logger.warn(
            'Enabling the profiling "no signals" workaround because an incompatible version of the mysql2 gem is ' \
            'installed. Profiling data will have lower quality. ' \
            'To fix this, upgrade the libmysqlclient in your OS image to version 8.0.0 or above.'
          )
          return true
        end

        if Gem.loaded_specs['rugged']
          Datadog.logger.warn(
            'Enabling the profiling "no signals" workaround because the rugged gem is installed. ' \
            'This is needed because some operations on this gem are currently incompatible with the normal working mode ' \
            'of the profiler, as detailed in <https://github.com/datadog/dd-trace-rb/issues/2721>. ' \
            'Profiling data will have lower quality.'
          )
          return true
        end

        if defined?(::PhusionPassenger)
          Datadog.logger.warn(
            'Enabling the profiling "no signals" workaround because the passenger web server is in use. ' \
            'This is needed because passenger is currently incompatible with the normal working mode ' \
            'of the profiler, as detailed in <https://github.com/DataDog/dd-trace-rb/issues/2976>. ' \
            'Profiling data will have lower quality.'
          )
          return true
        end

        false
      end

      # Versions of libmysqlclient prior to 8.0.0 are known to have buggy handling of system call interruptions.
      # The profiler can sometimes cause system call interruptions, and so this combination can cause queries to fail.
      #
      # See https://bugs.mysql.com/bug.php?id=83109 and
      # https://docs.datadoghq.com/profiler/profiler_troubleshooting/ruby/#unexpected-run-time-failures-and-errors-from-ruby-gems-that-use-native-extensions-in-dd-trace-rb-1110
      # for details.
      #
      # The `mysql2` gem's `info` method can be used to determine which `libmysqlclient` version is in use, and thus to
      # detect if it's safe for the profiler to use signals or if we need to employ a fallback.
      private_class_method def self.incompatible_libmysqlclient_version?(settings)
        return true if settings.profiling.advanced.skip_mysql2_check

        Datadog.logger.debug(
          'Requiring `mysql2` to check if the `libmysqlclient` version it uses is compatible with profiling'
        )

        begin
          require 'mysql2'

          # The mysql2-aurora gem likes to monkey patch itself in replacement of Mysql2::Client, and uses
          # `method_missing` to delegate to the original BUT unfortunately does not implement `respond_to_missing?` and
          # thus our `respond_to?(:info)` below was failing.
          #
          # But on the bright side, the gem does stash a reference to the original Mysql2::Client class in a constant,
          # so if that constant exists, we use that for our probing.
          mysql2_client_class =
            if defined?(Mysql2::Aurora::ORIGINAL_CLIENT_CLASS)
              Mysql2::Aurora::ORIGINAL_CLIENT_CLASS
            elsif defined?(Mysql2::Client)
              Mysql2::Client
            end

          return true unless mysql2_client_class && mysql2_client_class.respond_to?(:info)

          libmysqlclient_version = Gem::Version.new(mysql2_client_class.info[:version])

          compatible = libmysqlclient_version >= Gem::Version.new('8.0.0')

          Datadog.logger.debug(
            "The `mysql2` gem is using #{compatible ? 'a compatible' : 'an incompatible'} version of " \
            "the `libmysqlclient` library (#{libmysqlclient_version})"
          )

          !compatible
        rescue StandardError, LoadError => e
          Datadog.logger.warn(
            'Failed to probe `mysql2` gem information. ' \
            "Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
          )

          true
        end
      end

      # The old profiler's pprof support conflicts with the ruby-cloud-profiler gem.
      #
      # This is not a problem for almost all customers, since we now default everyone to use the new CPU Profiling 2.0
      # profiler. But the issue was still triggered, because currently we still _load_ both the old and new profiling
      # code paths.
      #
      # To work around this issue, and because we plan on deleting the old profiler soon, rather than poking at the
      # pprof support code, we only load the conflicting file when the old profiler is in use. This way customers using
      # the new profiler will not be affected by the issue any longer.
      private_class_method def self.load_pprof_support
        require_relative 'pprof/pprof_pb'
      end
    end
  end
end
