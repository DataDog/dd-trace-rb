module Datadog
  module Contrib
    module Mysql2
      # Mysql2 integration constants
      module Ext
        APP = 'mysql2'.freeze
        SERVICE_NAME = 'mysql2'.freeze

        SPAN_QUERY = 'mysql2.query'.freeze

        TAG_DB_NAME = 'mysql2.db.name'.freeze
      end
    end
  end
end
