module Datadog
  module Tracing
    module Contrib
      module MongoDB
        # MongoDB integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_MONGO_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_MONGO_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_MONGO_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_MONGO_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'mongodb'.freeze
          SPAN_COMMAND = 'mongo.cmd'.freeze
          SPAN_TYPE_COMMAND = 'mongodb'.freeze
          TAG_COLLECTION = 'mongodb.collection'.freeze
          TAG_DB = 'mongodb.db'.freeze
          TAG_OPERATION = 'mongodb.operation'.freeze
          TAG_QUERY = 'mongodb.query'.freeze
          TAG_ROWS = 'mongodb.rows'.freeze
          TAG_COMPONENT = 'mongodb'.freeze
          TAG_OPERATION_COMMAND = 'command'.freeze
          TAG_SYSTEM = 'mongodb'.freeze

          # Temporary namespace to accommodate unified tags which has naming collision, before
          # making breaking changes
          module DB
            TAG_COLLECTION = 'db.mongodb.collection'.freeze
          end
        end
      end
    end
  end
end
