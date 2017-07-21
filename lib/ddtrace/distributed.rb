require 'ddtrace/span'

module Datadog
  # Common code related to distributed tracing.
  module Distributed
    module_function

    # Parses a trace_id and a parent_id, typically sent as headers in
    # a distributed tracing context, and returns a couple of trace_id,parent_id
    # which are garanteed to be both non-zero. This does not 100% ensure they
    # are valid (after all, the caller could mess up data) but at least it
    # sorts out most common errors, such as syntax, nil values, etc.
    # Both headers must be set, else nil values are returned, for both.
    # Reports problem on debug log.
    def parse_trace_headers(trace_id_header, parent_id_header)
      return nil, nil if trace_id_header.nil? || parent_id_header.nil?
      trace_id = trace_id_header.to_i
      parent_id = parent_id_header.to_i
      if trace_id.zero?
        Datadog::Tracer.log.debug("invalid trace_id header: #{trace_id_header}")
        return nil, nil
      end
      if parent_id.zero?
        Datadog::Tracer.log.debug("invalid parent_id header: #{parent_id_header}")
        return nil, nil
      end
      if trace_id < 0 || trace_id >= Datadog::Span::MAX_ID
        Datadog::Tracer.log.debug("trace_id out of range: #{trace_id_header}")
        return nil, nil
      end
      if parent_id < 0 || parent_id >= Datadog::Span::MAX_ID
        Datadog::Tracer.log.debug("parent_id out of range: #{parent_id_header}")
        return nil, nil
      end
      [trace_id, parent_id]
    end
  end
end
