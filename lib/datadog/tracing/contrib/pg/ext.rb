module Datadog
  module Tracing
    module Contrib
      module Pg
        # pg integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_PG_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_PG_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_PG_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_PG_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'pg'.freeze
          SPAN_EXEC = 'pg.exec'.freeze
          SPAN_EXEC_PARAMS = 'pg.exec.params'.freeze
          SPAN_EXEC_PREPARED = 'pg.exec.prepared'.freeze
          SPAN_ASYNC_EXEC = 'pg.async.exec'.freeze
          SPAN_ASYNC_EXEC_PARAMS = 'pg.async.exec.params'.freeze
          SPAN_ASYNC_EXEC_PREPARED = 'pg.async.exec.prepared'.freeze
          SPAN_SYNC_EXEC = 'pg.sync.exec'.freeze
          SPAN_SYNC_EXEC_PARAMS = 'pg.sync.exec.params'.freeze
          SPAN_SYNC_EXEC_PREPARED = 'pg.sync.exec.prepared'.freeze
          TAG_DB_NAME = 'pg.db.name'.freeze
          TAG_COMPONENT = 'pg'.freeze
          TAG_OPERATION_QUERY = 'query'.freeze

          TAG_SYSTEM = 'postgresql'.freeze
        end
      end
    end
  end
end
