# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ActiveStorage
        # ActiveStorage integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          APP = 'active_storage'
          ENV_ENABLED = 'DD_TRACE_ACTIVE_STORAGE_ENABLED'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_STORAGE_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_STORAGE_ANALYTICS_SAMPLE_RATE'
          SERVICE_NAME = 'active_storage'
          SPAN_DELETE = 'active_storage.delete'
          SPAN_DELETE_PREFIXED = 'active_storage.delete_prefixed'
          SPAN_DOWNLOAD = 'active_storage.download'
          SPAN_DOWNLOAD_CHUNK = 'active_storage.download_chunk'
          SPAN_EXIST = 'active_storage.exist'
          SPAN_PREVIEW = 'active_storage.preview'
          SPAN_STREAMING_DOWNLOAD = 'active_storage.streaming_download'
          SPAN_TRANSFORM = 'active_storage.transform'
          SPAN_UPDATE_METADATA = 'active_storage.update_metadata'
          SPAN_UPLOAD = 'active_storage.upload'
          SPAN_URL = 'active_storage.url'
          TAG_SERVICE = 'active_storage.service'
          TAG_KEY = 'active_storage.key'
          TAG_PREFIX = 'active_storage.prefix'
          TAG_RANGE = 'active_storage.range'
          TAG_URL = 'active_storage.url'
          TAG_EXIST = 'active_storage.exist'
          TAG_CONTENT_TYPE = 'active_storage.content_type'
          TAG_DISPOSITION = 'active_storage.disposition'
          TAG_COMPONENT = 'active_storage'
          TAG_OPERATION_DELETE = 'delete'
          TAG_OPERATION_DELETE_PREFIXED = 'delete_prefixed'
          TAG_OPERATION_DOWNLOAD = 'download'
          TAG_OPERATION_DOWNLOAD_CHUNK = 'download_chunk'
          TAG_OPERATION_EXIST = 'exist'
          TAG_OPERATION_PREVIEW = 'preview'
          TAG_OPERATION_STREAMING_DOWNLOAD = 'streaming_download'
          TAG_OPERATION_TRANSFORM = 'transform'
          TAG_OPERATION_UPDATE_METADATA = 'update_metadata'
          TAG_OPERATION_UPLOAD = 'upload'
          TAG_OPERATION_URL = 'url'
        end
      end
    end
  end
end
