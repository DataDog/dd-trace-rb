# typed: false

require_relative 'sql_comment/comment'
require_relative 'sql_comment/ext'

module Datadog
  module Tracing
    module Contrib
      module Propagation
        module SqlComment
          Mode = Struct.new(:mode) do
            def enabled?
              mode != Ext::DISABLED
            end

            def service?
              mode == Ext::SERVICE
            end

            def full?
              mode == Ext::FULL
            end
          end

          def self.annotate!(span_op, mode)
            return unless mode.enabled?

            span_op.set_tag(Ext::TAG_DBM_TRACE_INJECTED, true) if mode.full?
          end

          def self.prepend_comment(sql, span_op, mode, tags: {})
            return sql unless mode.enabled?

            tags.merge!(service_context)
            tags.merge!(trace_context(span_op)) if mode.full?

            "#{Comment.new(tags)} #{sql}"
          end

          private

          def self.service_context
            {
              dde:  datadog_configuration.env,
              ddps: datadog_configuration.service,
              ddpv: datadog_configuration.version
            }
          end

          def self.datadog_configuration
            Datadog.configuration
          end

          # TODO: Derive from span_op
          def self.trace_context(_span_op)
            {
              # traceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
            }.freeze
          end
        end
      end
    end
  end
end
