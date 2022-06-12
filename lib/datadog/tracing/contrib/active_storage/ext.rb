# typed: true

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # ActiveStorage integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          APP = 'active_storage'.freeze
          ENV_ENABLED = 'DD_TRACE_ACTIVE_STORAGE_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_STORAGE_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_STORAGE_ANALYTICS_SAMPLE_RATE'.freeze
          SERVICE_NAME = 'active_storage'.freeze
          SPAN_ACTION = 'active_storage.action'.freeze
          TAG_SERVICE = 'active_storage.service'.freeze
          TAG_KEY = 'active_storage.key'.freeze
          TAG_PREFIX = 'active_storage.prefix'.freeze
          TAG_RANGE = 'active_storage.range'.freeze
          TAG_URL = 'active_storage.url'.freeze
          TAG_EXIST = 'active_storage.exist'.freeze
          TAG_CONTENT_TYPE = 'active_storage.content_type'.freeze
          TAG_DISPOSITION = 'active_storage.disposition'.freeze
          ACTION_DELETE = 'delete'.freeze
          ACTION_DELETE_PREFIXED = 'delete_prefixed'.freeze
          ACTION_DOWNLOAD = 'download'.freeze
          ACTION_DOWNLOAD_CHUNK = 'download_chunk'.freeze
          ACTION_EXIST = 'exist'.freeze
          ACTION_PREVIEW = 'preview'.freeze
          ACTION_STREAMING_DOWNLOAD = 'streaming_download'.freeze
          ACTION_TRANSFORM = 'transform'.freeze
          ACTION_UPDATE_METADATA = 'update_metadata'.freeze
          ACTION_UPLOAD = 'upload'.freeze
          ACTION_URL = 'url'.freeze
        end
      end
    end
  end
end
