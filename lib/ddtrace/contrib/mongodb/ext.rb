module Datadog
  module Contrib
    module MongoDB
      # MongoDB integration constants
      module Ext
        APP = 'mongodb'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_MONGO_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_MONGO_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'mongodb'.freeze
        SPAN_COMMAND = 'mongo.cmd'.freeze
        SPAN_TYPE_COMMAND = 'mongodb'.freeze
        TAG_COLLECTION = 'mongodb.collection'.freeze
        TAG_DB = 'mongodb.db'.freeze
        TAG_OPERATION = 'mongodb.operation'.freeze
        TAG_QUERY = 'mongodb.query'.freeze
        TAG_ROWS = 'mongodb.rows'.freeze
      end
    end
  end
end
