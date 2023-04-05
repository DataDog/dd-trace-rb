# frozen_string_literal: true

module Datadog
  module Tracing
    # Contains methods for fetching values according to span attributes schema
    module SpanAttributeSchema
      module Ext
       DEFAULT_VERSION = 'v0'.freeze
       VERSION_ONE = 'v1'.freeze
      end

      module_function

      def fetch_service_name(env, default)
        ENV.fetch(env) do
          if Datadog.configuration.tracing.span_attribute_schema == Ext::VERSION_ONE
            Datadog.configuration.service
          else
            default
          end
        end
      end

      def default_span_attribute_schema?
        Datadog.configuration.tracing.span_attribute_schema == Ext::DEFAULT_VERSION
      end

      def get_schema_version_numeric(version = Ext::DEFAULT_VERSION)
        if version == Ext::VERSION_ONE
          return 1
        end
        return 0
      end

    end
  end
end
