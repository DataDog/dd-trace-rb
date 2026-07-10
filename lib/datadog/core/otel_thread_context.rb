# frozen_string_literal: true

module Datadog
  module Core
    # Publishes a per-thread OpenTelemetry context record (trace id, span id) into a
    # thread-local slot, so an out-of-process reader (e.g. the eBPF profiler) can discover it.
    # See the "OTel Thread Context" OTEP (open-telemetry/opentelemetry-specification#4947).
    #
    # APIs in this module are implemented as native code; see ext/libdatadog_api/otel_thread_ctx.c.
    # Linux-only: `supported?` is `false` everywhere else.
    module OTelThreadContext
      module ThreadExtensions
        def initialize(*args, &block)
          super(*args) do |*block_args|
            Datadog::Core::OTelThreadContext._native_attach_new

            begin
              block.call(*block_args)
            ensure
              Datadog::Core::OTelThreadContext._native_detach_and_free
            end
          end
        end
      end

      def self.supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil? && _native_supported?
      end

      def self.enable!
        return false unless supported?

        Thread.prepend(ThreadExtensions) unless Thread.ancestors.include?(ThreadExtensions)

        true
      end

      # Debug helper: returns a Hash with the raw fields of the context record currently
      # attached to the calling thread (`trace_id`, `span_id`, `valid`, `attrs_data`), or
      # `nil` if no context is attached.
      def self.debug_peek
        _native_debug_peek
      end
    end
  end
end
