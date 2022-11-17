# typed: false

require_relative 'sql_comment/comment'
require_relative 'sql_comment/ext'

module Datadog
  module Tracing
    module Contrib
      module Propagation
        # Implements sql comment propagation related contracts.
        module SqlComment
          def self.annotate!(span_op, mode)
            return unless mode.enabled?

            # PENDING: Until `traceparent`` implementation in `full` mode
            # span_op.set_tag(Ext::TAG_DBM_TRACE_INJECTED, true) if mode.full?
          end

          def self.prepend_comment(sql, span_op, mode)
            return sql unless mode.enabled?

            tags = {
              Ext::KEY_DATABASE_SERVICE => span_op.service,
              Ext::KEY_ENVIRONMENT => datadog_configuration.env,
              Ext::KEY_PARENT_SERVICE => datadog_configuration.service,
              Ext::KEY_VERSION => datadog_configuration.version
            }

            # PENDING: Until `traceparent`` implementation in `full` mode
            # tags.merge!(trace_context(span_op)) if mode.full?

            "#{Comment.new(tags)} #{sql}"
          end

          def self.datadog_configuration
            Datadog.configuration
          end

          # TODO: Derive from trace
          def self.trace_context(_)
            {
              # traceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
            }.freeze
          end
        end
      end
    end
  end
end
