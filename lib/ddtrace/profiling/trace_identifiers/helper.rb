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
        def initialize(supported_apis: [::Datadog::Profiling::TraceIdentifiers::Ddtrace.new])
          @supported_apis = supported_apis
        end

        def trace_identifiers_for(thread)
          @supported_apis.each do |api|
            trace_identifiers = api.trace_identifiers_for(thread)
            return trace_identifiers unless trace_identifiers.nil?
          end

          nil
        end
      end
    end
  end
end
