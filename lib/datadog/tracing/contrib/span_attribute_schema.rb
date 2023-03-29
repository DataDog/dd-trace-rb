module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        def fetch_service_name(env, default)
          ENV.fetch(env) do
            if Datadog.configuration.tracing.span_attribute_schema == 'v1'
              Datadog.configuration.service
            else
              default
            end
          end
        end

        def default_span_attribute_schema?
          Datadog.configuration.tracing.span_attribute_schema ==
            Tracing::Configuration::Ext::SpanAttributeSchema::ENV_DEFAULT_SCHEMA
        end
      end
    end
  end
end
