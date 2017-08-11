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

        # TODO: move in the parser.rb
        # return a Command from the given MongoDB query
        def normalize_query(query)
          # remove the _id value
          query.each do |command|
            command.delete(:_id)
            command.each do |key, _|
              command[key] = '?'
            end
          end
          query
        end

        def started(event)
          pin = Datadog::Pin.get_from(event.address)
          return unless pin || !pin.enabled?

          # TODO: make all safe
          # start a trace and store it in the active span manager; using the `operation_id`
          # is safe since it's a unique id used to link events together. Reference:
          # https://github.com/mongodb/mongo-ruby-driver/blob/master/lib/mongo/monitoring.rb#L70
          command_name = event.command_name
          span = pin.tracer.trace('mongo.cmd', service: pin.service, span_type: 'mongodb')

          # some commands have special cases
          case command_name
          when :dropDatabase
            collection = nil
          else
            collection = event.command[command_name]
            span.set_tag('mongodb.collection', collection)
            span.set_tag('mongodb.ordered', event.command['ordered'])

            # get and normalize documents list; some commands don't have documents
            documents = event.command['documents']
            span.set_tag('mongodb.documents', normalize_query(documents)) unless documents.nil?
            documents ||= ''
          end

          # common fields
          span.set_tag('mongodb.db', event.database_name)
          span.set_tag('out.host', event.address.host)
          span.set_tag('out.port', event.address.port)

          # set the resource
          span.resource = "#{command_name} #{collection} #{documents}".strip
          @active_spans[event.operation_id] = span
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
            # whatever happens, the Hash must be clean and the span must be
            # finished to prevent any leak
            span.finish()
            @active_spans.delete(event.operation_id)
          end
        end
      end
    end
  end
end
