module Datadog
  module Contrib
    module Sequel
      # Sequel integration constants
      module Ext
        APP = 'sequel'.freeze
        SERVICE_NAME = 'sequel'.freeze

        SPAN_QUERY = 'sequel.query'.freeze

        TAG_DB_VENDOR = 'sequel.db.vendor'.freeze
      end
    end
  end
end
