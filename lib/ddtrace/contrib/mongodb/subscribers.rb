module Datadog
  module Contrib
    module MongoDB
      # `MongoCommandSubscriber` listens to all events from the `Monitoring`
      # system available in the Mongo driver.
      class MongoCommandSubscriber
        def initialize
          # keeps track of active Spans so that they can be retrieved
          # between executions. This data structure must be thread-safe.
          # TODO: add thread-safety
          @active_spans = {}
        end

        def started(event)
          pin = Datadog::Pin.get_from(event.address)
          return unless pin || !pin.enabled?

          # start a trace and store it in the active span manager; using the `operation_id`
          # is safe since it's a unique id used to link events together. Reference:
          # https://github.com/mongodb/mongo-ruby-driver/blob/master/lib/mongo/monitoring.rb#L70
          span = pin.tracer.trace('mongo.cmd', service: pin.service, span_type: 'mongodb')
          @active_spans[event.operation_id] = span

          # common fields for all commands
          command_name = event.command_name
          collection = event.command[command_name]
          span.set_tag('mongodb.collection', collection)
          span.set_tag('mongodb.db', event.database_name)
          span.set_tag('out.host', event.address.host)
          span.set_tag('out.port', event.address.port)

          # commands are handled so that specific fields are normalized based on type, if it's
          # a command that requires documents or a specific query. For some commands, we only
          # take in consideration the query ('q') to keep the cardinality low
          # NOTE: 'find' doesn't use a symbol
          case command_name
          when "find"
            filter = event.command['filter']
            unless filter.nil? || filter.empty?
              query = Datadog::Contrib::MongoDB.normalize_query(filter)
              span.set_tag('mongodb.filter', query)
            end
          when :update
            updates = event.command['updates']
            unless updates.nil? || updates.empty? || updates.first['q'].empty?
              query = Datadog::Contrib::MongoDB.normalize_query(updates.first['q'])
              span.set_tag('mongodb.updates', query)
            end
          when :delete
            deletes = event.command['deletes']
            unless deletes.nil? || deletes.empty? || deletes.first['q'].empty?
              query = Datadog::Contrib::MongoDB.normalize_query(deletes.first['q'])
              span.set_tag('mongodb.deletes', query)
            end
          else
            span.set_tag('mongodb.ordered', event.command['ordered'])

            documents = event.command['documents']
            unless documents.nil? || documents.empty?
              document = Datadog::Contrib::MongoDB.normalize_documents(documents)
              span.set_tag('mongodb.documents', document)
            end
          end

          # set the resource with the quantized documents or queries
          span.resource = "#{command_name} #{collection} #{document || query}".strip
        end

        def failed(event)
          # TODO: find the error? at least flag it as error
          finished(event)
        end

        def succeeded(event)
          finished(event)
        end

        def finished(event)
          begin
            # retrieve the span from the manager and add fields that
            # are known only when the query is finished
            span = @active_spans[event.operation_id]
            rows = event.reply.fetch('n', nil)
            span.set_tag('mongodb.rows', rows) unless rows.nil?
          ensure
            # whatever happens, the Span must be removed from the Hash and it must be
            # finished to prevent any leak
            span.finish()
            @active_spans.delete(event.operation_id)
          end
        end
      end
    end
  end
end
