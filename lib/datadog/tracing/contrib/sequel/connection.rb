# frozen_string_literal: true

require_relative "ext"
require_relative "utils"

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Adds instrumentation to Sequel connection execution
        module Connection
          def log_connection_yield(sql, conn, args = nil, &block)
            span = Datadog::Tracing.active_span

            if span && span.name == Ext::SPAN_QUERY
              Utils.set_connection_tags(span, conn)
            end

            super
          end
        end
      end
    end
  end
end
