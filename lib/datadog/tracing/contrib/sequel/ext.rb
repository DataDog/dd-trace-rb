# frozen_string_literal: true

require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Sequel integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = "DD_TRACE_SEQUEL_ENABLED"
          # @!visibility private
          ENV_ANALYTICS_ENABLED = "DD_TRACE_SEQUEL_ANALYTICS_ENABLED"
          ENV_ANALYTICS_SAMPLE_RATE = "DD_TRACE_SEQUEL_ANALYTICS_SAMPLE_RATE"
          SPAN_QUERY = "sequel.query"
          TAG_DB_VENDOR = "sequel.db.vendor"
          TAG_PREPARED_NAME = "sequel.prepared.name"
          TAG_COMPONENT = "sequel"
          TAG_OPERATION_QUERY = "query"
          TAG_DB_NAME = "sequel.db.name"
          PEER_SERVICE_SOURCES = ([TAG_DB_NAME] + Contrib::Ext::DB::PEER_SERVICE_SOURCES).freeze
        end
      end
    end
  end
end
