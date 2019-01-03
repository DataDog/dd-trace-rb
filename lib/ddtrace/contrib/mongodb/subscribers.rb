require 'ddtrace/contrib/mongodb/ext'
require 'ddtrace/contrib/mongodb/parsers'

module Datadog
  module Contrib
    module MongoDB
      # `MongoCommandSubscriber` listens to all events from the `Monitoring`
      # system available in the Mongo driver.
      class MongoCommandSubscriber
        def started(event)
          pin = Datadog::Pin.get_from(event.address)
          return unless pin && pin.enabled?

          # start a trace and store it in the current thread; using the `operation_id`
          # is safe since it's a unique id used to link events together. Also only one
          # thread is involved in this execution so thread-local storage should be safe. Reference:
          # https://github.com/mongodb/mongo-ruby-driver/blob/master/lib/mongo/monitoring.rb#L70
          # https://github.com/mongodb/mongo-ruby-driver/blob/master/lib/mongo/monitoring/publishable.rb#L38-L56
          span = pin.tracer.trace(Ext::SPAN_COMMAND, service: pin.service, span_type: Ext::SPAN_TYPE_COMMAND)
          Thread.current[:datadog_mongo_span] ||= {}
          Thread.current[:datadog_mongo_span][event.request_id] = span

          # build a quantized Query using the Parser module
          query = MongoDB.query_builder(event.command_name, event.database_name, event.command)
          serialized_query = query.to_s

          # add operation tags; the full query is stored and used as a resource,
          # since it has been quantized and reduced
          span.set_tag(Ext::TAG_DB, query['database'])
          span.set_tag(Ext::TAG_COLLECTION, query['collection'])
          span.set_tag(Ext::TAG_OPERATION, query['operation'])
          span.set_tag(Ext::TAG_QUERY, serialized_query)
          span.set_tag(Datadog::Ext::NET::TARGET_HOST, event.address.host)
          span.set_tag(Datadog::Ext::NET::TARGET_PORT, event.address.port)

          # set the resource with the quantized query
          span.resource = serialized_query
        end

        def failed(event)
          span = Thread.current[:datadog_mongo_span][event.request_id]
          return unless span

          # the failure is not a real exception because it's handled by
          # the framework itself, so we set only the error and the message
          span.set_error(event)
        rescue StandardError => e
          Datadog::Tracer.log.debug("error when handling MongoDB 'failed' event: #{e}")
        ensure
          # whatever happens, the Span must be removed from the local storage and
          # it must be finished to prevent any leak
          span.finish unless span.nil?
          Thread.current[:datadog_mongo_span].delete(event.request_id)
        end

        def succeeded(event)
          span = Thread.current[:datadog_mongo_span][event.request_id]
          return unless span

          # add fields that are available only after executing the query
          rows = event.reply.fetch('n', nil)
          span.set_tag(Ext::TAG_ROWS, rows) unless rows.nil?
        rescue StandardError => e
          Datadog::Tracer.log.debug("error when handling MongoDB 'succeeded' event: #{e}")
        ensure
          # whatever happens, the Span must be removed from the local storage and
          # it must be finished to prevent any leak
          span.finish unless span.nil?
          Thread.current[:datadog_mongo_span].delete(event.request_id)
        end
      end
    end
  end
end
