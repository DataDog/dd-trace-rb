# frozen_string_literal: true

require "json"
require_relative "../../../data_streams"
require_relative "../../../core/utils/base64_codec"

module Datadog
  module Tracing
    module Contrib
      module Aws
        # Data Streams Monitoring checkpoints for SQS and SNS, carried in the `_datadog` message attribute.
        module DataStreams
          ATTRIBUTE_NAME = "_datadog"
          MAX_MESSAGE_ATTRIBUTES = 10
          BASE64_TEXT = %r{\A(?:[A-Za-z0-9+/]{4})+(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z}.freeze

          class << self
            def before_request(service, operation, context)
              return unless Datadog::DataStreams.enabled?

              case [service, operation]
              when ["sqs", :send_message]
                context.params = inject_sqs(context.params, queue_name(context.params))
              when ["sqs", :send_message_batch]
                queue = queue_name(context.params)
                context.params = with_entries(context.params) { |entry| inject_sqs(entry, queue) }
              when ["sqs", :receive_message]
                context.params = request_datadog_attribute(context.params)
              when ["sns", :publish]
                context.params = inject_sns(context.params, sns_destination(context.params))
              when ["sns", :publish_batch]
                topic = sns_destination(context.params)
                context.params = with_entries(context.params) { |entry| inject_sns(entry, topic) }
              end
            rescue => e
              Datadog.logger.debug { "Error setting DSM produce checkpoint: #{e.class}: #{e.message}" }
            end

            def after_response(service, operation, context, response)
              return unless service == "sqs" && operation == :receive_message
              return unless Datadog::DataStreams.enabled?

              queue = queue_name(context.params)
              return unless queue

              messages = response.data&.messages || []
              caller_context = Datadog::DataStreams.pathway_context
              messages.each { |message| consume(queue, message) }
              # Only the sole message's context can be safely left active for the
              # caller; a batch's last one would misattribute the others' downstream work.
              Datadog::DataStreams.pathway_context = caller_context unless messages.size == 1
            rescue => e
              Datadog.logger.debug { "Error setting DSM consume checkpoint: #{e.class}: #{e.message}" }
            end

            private

            def consume(queue, message)
              carrier = extract_carrier(message)
              pathway = carrier && unwrap_double_encoding(carrier[Datadog::DataStreams::Processor::PROPAGATION_KEY])
              Datadog::DataStreams.pathway_context = nil
              Datadog::DataStreams.set_consume_checkpoint(type: "sqs", source: queue, auto_instrumentation: true) do |_key|
                pathway
              end
            rescue => e
              Datadog.logger.debug { "Error setting DSM consume checkpoint: #{e.class}: #{e.message}" }
            end

            def inject_sqs(message, queue)
              return message unless queue

              inject(message, "sqs", queue) do |carrier|
                {data_type: "String", string_value: JSON.generate(carrier)}
              end
            end

            def inject_sns(message, topic)
              return message unless topic

              inject(message, "sns", topic) do |carrier|
                {data_type: "Binary", binary_value: JSON.generate(carrier)}
              end
            end

            def inject(message, type, destination)
              attributes = message[:message_attributes] || {}
              existing = attributes[ATTRIBUTE_NAME] || attributes[ATTRIBUTE_NAME.to_sym]
              return message if existing.nil? && attributes.size >= MAX_MESSAGE_ATTRIBUTES

              carrier = existing ? parse_attribute_hash(existing) : {}
              return message unless carrier

              Datadog::DataStreams.set_produce_checkpoint(type: type, destination: destination, auto_instrumentation: true) do |key, value|
                carrier[key] = value
              end

              attributes = attributes.reject { |name, _| name.to_s == ATTRIBUTE_NAME }
              message.merge(message_attributes: attributes.merge(ATTRIBUTE_NAME => yield(carrier)))
            end

            def with_entries(params)
              entries = params[:entries] || params[:publish_batch_request_entries]
              return params unless entries

              key = params.key?(:entries) ? :entries : :publish_batch_request_entries
              params.merge(key => entries.map { |entry| yield(entry) })
            end

            def request_datadog_attribute(params)
              names = (params[:message_attribute_names] || []).map(&:to_s)
              return params if names.include?(ATTRIBUTE_NAME) || names.include?("All") || names.include?(".*")

              params.merge(message_attribute_names: names + [ATTRIBUTE_NAME])
            end

            def extract_carrier(message)
              attribute = message.message_attributes&.[](ATTRIBUTE_NAME)
              return parse_json(attribute.string_value || attribute.binary_value) if attribute

              envelope = parse_json(message.body)
              return unless envelope && envelope["Type"] == "Notification"

              notification_attribute = envelope.dig("MessageAttributes", ATTRIBUTE_NAME)
              return unless notification_attribute.is_a?(Hash)

              value = notification_attribute["Value"]
              value = Core::Utils::Base64Codec.strict_decode64(value) if notification_attribute["Type"] == "Binary"
              parse_json(value)
            end

            # .NET base64-encodes the pathway twice. A once-encoded pathway decodes to varint
            # bytes with the high bit set, never base64 text, so this cannot misfire.
            def unwrap_double_encoding(value)
              return value unless value.is_a?(String) && BASE64_TEXT.match?(value)

              decoded = Core::Utils::Base64Codec.strict_decode64(value)
              BASE64_TEXT.match?(decoded) ? decoded : value
            rescue ArgumentError
              value
            end

            def parse_attribute_hash(attribute)
              value = attribute[:string_value] || attribute[:binary_value] ||
                attribute["string_value"] || attribute["binary_value"]
              parse_json(value)
            end

            def parse_json(value)
              return unless value.is_a?(String)

              parsed = JSON.parse(value)
              parsed if parsed.is_a?(Hash)
            rescue JSON::ParserError
              nil
            end

            def queue_name(params)
              url = params[:queue_url]
              url&.split("/")&.last
            end

            def sns_destination(params)
              params[:topic_arn] || params[:target_arn]
            end
          end
        end
      end
    end
  end
end
