# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Contains methods for fetching values according to span attributes schema
      module SpanAttributeSchema
        module_function

        # rubocop:disable Style/OptionalArguments
        def fetch_service_name(value = nil, default)
          if value
            value
          elsif Datadog.configuration.tracing.span_attribute_schema ==
              Tracing::Configuration::Ext::SpanAttributeSchema::VERSION_ONE
            Datadog.configuration.service
          else
            default
          end
        end
        # rubocop:enable Style/OptionalArguments

        def default_span_attribute_schema?
          Datadog.configuration.tracing.span_attribute_schema ==
            Tracing::Configuration::Ext::SpanAttributeSchema::DEFAULT_VERSION
        end
      end
    end
  end
end
