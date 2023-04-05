# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        def fetch_service_name(env, default)
          ENV.fetch(env) do
            if Datadog.configuration.tracing.span_attribute_schema ==
                Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE
              Datadog.configuration.service
            else
              default
            end
          end
        end

        def default_span_attribute_schema?
          Datadog.configuration.tracing.span_attribute_schema ==
            Tracing::Configuration::Ext::SpanAttributeSchema::DEFAULT_VERSION
        end

        def get_schema_version_numeric(version = "v0")
          if version == "v1"
            return 1
          end
          return 0
        end

      end
    end
  end
end
