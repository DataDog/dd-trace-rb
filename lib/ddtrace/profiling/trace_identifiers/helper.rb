# frozen_string_literal: true

require 'ddtrace/profiling/trace_identifiers/ddtrace'

module Datadog
  module Profiling
    module TraceIdentifiers
      # Helper used to retrieve the trace identifiers (trace id and span id) for a given thread,
      # if there is an active trace for that thread for the supported tracing APIs.
      #
      # This data is used to connect profiles to the traces -- samples in a profile will be tagged with this data and
      # the profile can be filtered down to look at only the samples for a given trace.
      class Helper
        DEFAULT_SUPPORTED_APIS = [
          ::Datadog::Profiling::TraceIdentifiers::Ddtrace
        ].freeze
        private_constant :DEFAULT_SUPPORTED_APIS

        def initialize(
          tracer:,
          # If this is disabled, the helper will strip the optional trace_resource_container even if provided by the api
          extract_trace_resource:,
          supported_apis: DEFAULT_SUPPORTED_APIS.map { |api| api.new(tracer: tracer) }
        )
          @extract_trace_resource = extract_trace_resource
          @supported_apis = supported_apis
        end

        # Expected output of the #trace_identifiers_for
        # duck type is [trace_id, span_id, (optional trace_resource_container)]
        def trace_identifiers_for(thread)
          @supported_apis.each do |api|
            trace_identifiers = api.trace_identifiers_for(thread)

            if trace_identifiers
              return @extract_trace_resource ? trace_identifiers : trace_identifiers[0..1]
            end
          end

          nil
        end
      end
    end
  end
end
