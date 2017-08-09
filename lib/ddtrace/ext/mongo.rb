module Datadog
  module Ext
    module Mongo
      # type of the spans
      TYPE = 'mongodb'.freeze
      COLLECTION = 'mongodb.collection'.freeze
      DB = 'mongodb.db'.freeze
      ROWS = 'mongodb.rows'.freeze
      QUERY = 'mongodb.query'.freeze
    end
  end
end
