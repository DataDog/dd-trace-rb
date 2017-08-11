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
          span = pin.tracer.trace('mongo.cmd', service: pin.service, span_type: 'mongodb')
          Thread.current[:datadog_mongo_span] = span

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
          begin
            span = Thread.current[:datadog_mongo_span]
            return unless span

            # the failure is not a real exception because it's handled by
            # the framework itself, so setting the error and the message
            # should be enough
            span.status = 1
            span.set_tag(Datadog::Ext::Errors::MSG, event.message)
          ensure
            # whatever happens, the Span must be removed from the local storage and
            # it must be finished to prevent any leak
            span.finish() unless span.nil?
            Thread.current[:datadog_mongo_span] = nil
          end
        end

        def succeeded(event)
          begin
            span = Thread.current[:datadog_mongo_span]
            return unless span

            # add fields that are available only after executing the query
            rows = event.reply.fetch('n', nil)
            span.set_tag('mongodb.rows', rows) unless rows.nil?
          ensure
            # whatever happens, the Span must be removed from the local storage and
            # it must be finished to prevent any leak
            span.finish() unless span.nil?
            Thread.current[:datadog_mongo_span] = nil
          end
        end
      end
    end
  end
end
