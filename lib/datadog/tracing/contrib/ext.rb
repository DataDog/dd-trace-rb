# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Contrib specific constants
      module Ext
        # @public_api
        module DB
          TAG_INSTANCE = 'db.instance'
          TAG_USER = 'db.user'
          TAG_SYSTEM = 'db.system'
          TAG_STATEMENT = 'db.statement'
          TAG_ROW_COUNT = 'db.row_count'

          ELASTICSEARCH = 'elasticsearch'
          MEMCACHED = 'memcached'
          MONGODB = 'mongodb'
          MYSQL = 'mysql'
          REDIS = 'redis'
        end
      end
    end
  end
end
