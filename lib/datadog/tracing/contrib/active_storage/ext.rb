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
          SPAN_DELETE = 'active_storage.delete'.freeze
          SPAN_DELETE_PREFIXED = 'active_storage.delete_prefixed'.freeze
          SPAN_DOWNLOAD = 'active_storage.download'.freeze
          SPAN_DOWNLOAD_CHUNK = 'active_storage.download_chunk'.freeze
          SPAN_EXIST = 'active_storage.exist'.freeze
          SPAN_PREVIEW = 'active_storage.preview'.freeze
          SPAN_STREAMING_DOWNLOAD = 'active_storage.streaming_download'.freeze
          SPAN_TRANSFORM = 'active_storage.transform'.freeze
          SPAN_UPDATE_METADATA = 'active_storage.update_metadata'.freeze
          SPAN_UPLOAD = 'active_storage.upload'.freeze
          SPAN_URL = 'active_storage.url'.freeze
          TAG_SERVICE = 'active_storage.service'.freeze
          TAG_KEY = 'active_storage.key'.freeze
          TAG_PREFIX = 'active_storage.prefix'.freeze
          TAG_RANGE = 'active_storage.range'.freeze
          TAG_URL = 'active_storage.url'.freeze
          TAG_EXIST = 'active_storage.exist'.freeze
          TAG_CONTENT_TYPE = 'active_storage.content_type'.freeze
          TAG_DISPOSITION = 'active_storage.disposition'.freeze
        end
      end
    end
  end
end
