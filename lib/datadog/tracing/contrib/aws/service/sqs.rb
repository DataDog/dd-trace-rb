# frozen_string_literal: true

require_relative './base'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # SQS tag handlers.
          class SQS < Base
            DATATYPE = 'String'
            def before_span(config, context, response)
              return unless context.operation == :receive_message && config[:propagation]

              # Parent the current trace based on distributed message attributes
              extract_propagation!(response, 'string_value') if config[:parentage_style] == 'distributed'
            end

            def process(config, trace, context)
              return unless config[:propagation]

              case context.operation
              when :send_message
                inject_propagation(trace, context.params, 'String')
                # TODO: when :send_message_batch # Future support for batch sending
              end
            end

            def add_tags(span, params)
              queue_url = params[:queue_url]
              queue_name = params[:queue_name]
              if queue_url
                _, _, _, aws_account, queue_name = queue_url.split('/')
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, aws_account)
              end
              span.set_tag(Aws::Ext::TAG_QUEUE_NAME, queue_name)
            end
          end
        end
      end
    end
  end
end
