# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Base class for all AWS service-specific tag handlers.
          class Base
            def process(config, trace, context); end
            def add_tags(span, params); end

            MESSAGE_ATTRIBUTES_LIMIT = 10 # Can't set more than 10 message attributes

            def extract_propagation(context)
              message_attributes = context.params[:message_attributes]

              return unless message_attributes && (datadog = message_attributes['_datadog'])

              Tracing.continue_trace!(Contrib.extract(datadog))
            end

            def inject_propagation(trace, context, data_type)
              message_attributes = (context.params[:message_attributes] ||= {})
              return if message_attributes.size >= MESSAGE_ATTRIBUTES_LIMIT

              data = {}
              if Datadog::Tracing::Contrib.inject(trace.to_digest, data)
                message_attributes['_datadog'] = { :data_type => data_type, :binary_value => data.to_json }
              end
            end
          end
        end
      end
    end
  end
end
