module Datadog
  module Contrib
    module ActiveRecord
      # ActiveRecord integration constants
      module Ext
        APP = 'active_record'.freeze
        SERVICE_NAME = 'active_record'.freeze

        SPAN_INSTANTIATION = 'active_record.instantiation'.freeze
        SPAN_SQL = 'active_record.sql'.freeze

        SPAN_TYPE_INSTANTIATION = 'custom'.freeze

        TAG_DB_CACHED = 'active_record.db.cached'.freeze
        TAG_DB_NAME = 'active_record.db.name'.freeze
        TAG_DB_VENDOR = 'active_record.db.vendor'.freeze
        TAG_INSTANTIATION_CLASS_NAME = 'active_record.instantiation.class_name'.freeze
        TAG_INSTANTIATION_RECORD_COUNT = 'active_record.instantiation.record_count'.freeze
      end
    end
  end
end
