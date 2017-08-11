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
          # always take the first element to safe-guard against massive insert_many;
          # NOTE: this is a rough estimation because it's possible to insert
          # many values using different schemas; unfortunately to speed-up the
          # parsing process this is the best guess.
          # TODO: the normalization must be moved at Trace Agent level so that is
          # faster and more accurate
          document = query.first.dup

          # delete the unique identifier
          document.delete(:_id)
          document.each do |key, _|
            document[key] = '?'
          end

          document
        end

        # removes values from filter keys
        def normalize_filter(filter)
          norm_filter = filter.dup
          norm_filter.each do |key, _|
            norm_filter[key] = '?'
          end
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

            # get and normalize documents list
            documents = event.command['documents']
            unless documents.nil? || documents.empty?
              document = normalize_query(documents)
              span.set_tag('mongodb.documents', document)
            end

            # get and normalize filters list
            filters = event.command['filter']
            unless filters.nil? || filters.empty?
              filter = normalize_filter(filters)
              span.set_tag('mongodb.filter', filter)
            end

            updates = event.command['updates']
            unless updates.nil? || updates.empty? || updates.first['q'].empty?
              # we're only using the query parameter and
              # not the updated fields
              query = normalize_filter(updates.first['q'])
              span.set_tag('mongodb.updates', query)
            end

            deletes = event.command['deletes']
            unless deletes.nil? || deletes.empty? || deletes.first['q'].empty?
              # we're only using the query parameter and
              # not the updated fields
              query = normalize_filter(deletes.first['q'])
              span.set_tag('mongodb.deletes', query)
            end
          end

          # common fields
          span.set_tag('mongodb.db', event.database_name)
          span.set_tag('out.host', event.address.host)
          span.set_tag('out.port', event.address.port)

          # set the resource
          span.resource = "#{command_name} #{collection} #{document || filter || query}".strip
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
