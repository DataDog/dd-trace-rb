module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # ActiveRecord integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTIVE_RECORD_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_RECORD_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_RECORD_ANALYTICS_SAMPLE_RATE'.freeze
          SERVICE_NAME = 'active_record'.freeze
          SPAN_INSTANTIATION = 'active_record.instantiation'.freeze
          SPAN_SQL = 'active_record.sql'.freeze
          SPAN_TYPE_INSTANTIATION = 'custom'.freeze
          TAG_COMPONENT = 'active_record'.freeze
          TAG_OPERATION_INSTANTIATION = 'instantiation'.freeze
          TAG_OPERATION_SQL = 'sql'.freeze
          TAG_DB_CACHED = 'active_record.db.cached'.freeze
          TAG_DB_NAME = 'active_record.db.name'.freeze
          TAG_DB_VENDOR = 'active_record.db.vendor'.freeze
          TAG_INSTANTIATION_CLASS_NAME = 'active_record.instantiation.class_name'.freeze
          TAG_INSTANTIATION_RECORD_COUNT = 'active_record.instantiation.record_count'.freeze
        end
      end
    end
  end
end
