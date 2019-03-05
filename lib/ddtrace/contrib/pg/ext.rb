module Datadog
  module Contrib
    module Pg
      # PG integration constants
      module Ext
        APP = 'pg'.freeze
        SERVICE_NAME = 'pg'.freeze

        SPAN_QUERY = 'pg.query'.freeze

        TAG_DB_NAME = 'pg.db.name'.freeze
      end
    end
  end
end
