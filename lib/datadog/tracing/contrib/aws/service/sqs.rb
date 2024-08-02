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
            def before_span(config, context)
              if config[:propagation] && context.operation == :receive_message
                extract_propagation(context)
              end
            end

            def process(config, trace, context)
              return unless config[:propagation]

              case context.operation
              when :send_message
                inject_propagation(trace, context, 'String')
              when :send_message_batch
                if config[:batch_propagation]
                  inject_propagation(trace, context, 'String')
                else
                  inject_propagation(trace, context, 'String')
                end
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
