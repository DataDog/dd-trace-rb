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

          def self.annotate!(span, mode:)
            return unless mode.enabled?

            span.set_tag('_dd.dbm_trace_injected', true) if mode.full?
          end

          def self.prepend_comment(sql, span, tags: {}, mode:)
            return sql unless mode.enabled?

            tags.merge!(service_context)     if mode.full? || mode.service?
            tags.merge!(trace_context(span)) if mode.full?

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

          def self.trace_context(_span)
            {
              traceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' # TODO: Derive from span?
            }.freeze
          end
        end
      end
    end
  end
end
