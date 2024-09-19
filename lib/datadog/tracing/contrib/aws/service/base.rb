# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Base class for all AWS service-specific tag handlers.
          class Base
            def before_span(config, context, response); end
            def process(config, trace, context); end
            def add_tags(span, params); end

            MESSAGE_ATTRIBUTES_LIMIT = 10 # Can't set more than 10 message attributes

            # Extract the `_datadog` message attribute and decode its JSON content.
            def extract_propagation!(response, data_type)
              messages = response.data.messages

              # DEV: Extract the context from the first message today.
              # DEV: Use span links in the future to support multiple messages related to a single span.
              return unless (message = messages[0])

              message_attributes = message.message_attributes

              return unless message_attributes && (datadog = message_attributes['_datadog'])

              if (data = datadog[data_type]) && (parsed_data = JSON.parse(data))
                Tracing.continue_trace!(Distributed.extract(parsed_data))
              end
            end

            def inject_propagation(trace, params, data_type)
              message_attributes = (params[:message_attributes] ||= {})
              return if message_attributes.size >= MESSAGE_ATTRIBUTES_LIMIT

              data = {}
              if Distributed.inject(trace.to_digest, data)
                message_attributes['_datadog'] = { :data_type => data_type, :binary_value => data.to_json }
              end
            end
          end
        end
      end
    end
  end
end
