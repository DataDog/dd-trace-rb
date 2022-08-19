require_relative 'ext'
require_relative '../../metadata/ext'

module Datadog
  module Tracing
    module Contrib
      module Hanami
        # Hanami Instrumentation for `hanami.render`
        module RendererPolicyTracing
          def render(env, response)
            # Handle `nil`
            action = env['hanami.action']

            Tracing.trace(
              Ext::SPAN_RENDER,
              service: configuration[:service_name],
              resource: action.class.to_s,
              span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND
            ) do |span_op, _trace_op|
              span_op.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span_op.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_RENDER)

              super
            end
          end

          def configuration
            Datadog.configuration.tracing[:hanami]
          end
        end
      end
    end
  end
end
