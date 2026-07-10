# frozen_string_literal: true

module Datadog
  module Profiling
    module Collectors
      # Used to trigger sampling of threads, based on external "events", such as:
      # * periodic timer for cpu-time and wall-time
      # * VM garbage collection events
      # * VM object allocation events
      # Triggering of this component (e.g. watching for the above "events") is implemented by
      # Collectors::CpuAndWallTimeWorker.
      # The stack collection itself is handled using the Datadog::Profiling::Collectors::Stack.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_thread_context.c`
      class ThreadContext
        def initialize(
          recorder:,
          max_frames:,
          tracer:,
          endpoint_collection_enabled:,
          waiting_for_gvl_threshold_ns:,
          otel_context_enabled:,
          native_filenames_enabled:,
          include_module_name:
        )
          tracer_context_key = safely_extract_context_key_from(tracer)
          self.class._native_initialize(
            self_instance: self,
            recorder: recorder,
            max_frames: max_frames,
            tracer_context_key: tracer_context_key,
            endpoint_collection_enabled: endpoint_collection_enabled,
            waiting_for_gvl_threshold_ns: waiting_for_gvl_threshold_ns,
            otel_context_enabled: otel_context_enabled,
            native_filenames_enabled: validate_native_filenames(native_filenames_enabled),
            include_module_name: include_module_name,
            overhead_filename: __FILE__,
          )
        end

        def self.for_testing(
          recorder:,
          max_frames: 400,
          tracer: nil,
          endpoint_collection_enabled: false,
          waiting_for_gvl_threshold_ns: 10_000_000,
          otel_context_enabled: false,
          native_filenames_enabled: true,
          include_module_name: false,
          trigger_global_reset: true,
          **options
        )
          collector = new(
            recorder: recorder,
            max_frames: max_frames,
            tracer: tracer,
            endpoint_collection_enabled: endpoint_collection_enabled,
            waiting_for_gvl_threshold_ns: waiting_for_gvl_threshold_ns,
            otel_context_enabled: otel_context_enabled,
            native_filenames_enabled: native_filenames_enabled,
            include_module_name: include_module_name,
            **options,
          )

          # By default, mirror what the CpuAndWallTimeWorker does when profiling starts: reset the global per-thread
          # context state, which (among other things) resizes the per-thread sampling buffers to this collector's
          # max_frames. Tests that need to control this explicitly can pass `trigger_global_reset: false`.
          Testing._native_global_reset_per_thread_context(collector) if trigger_global_reset

          collector
        end

        def inspect
          # Compose Ruby's default inspect with our custom inspect for the native parts
          result = super
          result[-1] = "#{self.class._native_inspect(self)}>"
          result
        end

        def reset_after_fork
          self.class._native_reset_after_fork(self)
        end

        private

        def safely_extract_context_key_from(tracer)
          return unless tracer

          provider = tracer.respond_to?(:provider) && tracer.provider

          return unless provider

          context = provider.instance_variable_get(:@context)
          context&.instance_variable_get(:@key)
        end

        def validate_native_filenames(native_filenames_enabled)
          if native_filenames_enabled && !Datadog::Profiling::Collectors::Stack._native_filenames_available?
            Datadog.logger.debug(
              "Native filenames are enabled, but the required dladdr API was not available. Disabling native filenames."
            )
            false
          else
            native_filenames_enabled
          end
        end
      end
    end
  end
end
