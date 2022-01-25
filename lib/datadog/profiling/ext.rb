# typed: true
module Datadog
  module Profiling
    module Ext
      ENV_ENABLED = 'DD_PROFILING_ENABLED'.freeze
      ENV_UPLOAD_TIMEOUT = 'DD_PROFILING_UPLOAD_TIMEOUT'.freeze
      ENV_MAX_FRAMES = 'DD_PROFILING_MAX_FRAMES'.freeze
      ENV_AGENTLESS = 'DD_PROFILING_AGENTLESS'.freeze
      ENV_ENDPOINT_COLLECTION_ENABLED = 'DD_PROFILING_ENDPOINT_COLLECTION_ENABLED'.freeze

      module Pprof
        LABEL_KEY_LOCAL_ROOT_SPAN_ID = 'local root span id'.freeze
        LABEL_KEY_SPAN_ID = 'span id'.freeze
        LABEL_KEY_THREAD_ID = 'thread id'.freeze
        LABEL_KEY_TRACE_ENDPOINT = 'trace endpoint'.freeze
        SAMPLE_VALUE_NO_VALUE = 0
        VALUE_TYPE_CPU = 'cpu-time'.freeze
        VALUE_TYPE_WALL = 'wall-time'.freeze
        VALUE_UNIT_NANOSECONDS = 'nanoseconds'.freeze
      end

      module Transport
        module HTTP
          URI_TEMPLATE_DD_API = 'https://intake.profile.%s/'.freeze

          FORM_FIELD_RECORDING_START = 'start'.freeze
          FORM_FIELD_RECORDING_END = 'end'.freeze
          FORM_FIELD_FAMILY = 'family'.freeze
          FORM_FIELD_TAG_ENV = 'env'.freeze
          FORM_FIELD_TAG_HOST = 'host'.freeze
          FORM_FIELD_TAG_LANGUAGE = 'language'.freeze
          FORM_FIELD_TAG_PID = 'pid'.freeze
          FORM_FIELD_TAG_PROFILER_VERSION = 'profiler_version'.freeze
          FORM_FIELD_TAG_RUNTIME = 'runtime'.freeze
          FORM_FIELD_TAG_RUNTIME_ENGINE = 'runtime_engine'.freeze
          FORM_FIELD_TAG_RUNTIME_ID = 'runtime-id'.freeze
          FORM_FIELD_TAG_RUNTIME_PLATFORM = 'runtime_platform'.freeze
          FORM_FIELD_TAG_RUNTIME_VERSION = 'runtime_version'.freeze
          FORM_FIELD_TAG_SERVICE = 'service'.freeze
          FORM_FIELD_TAG_VERSION = 'version'.freeze
          FORM_FIELD_TAGS = 'tags'.freeze
          FORM_FIELD_INTAKE_VERSION = 'version'.freeze

          HEADER_CONTENT_TYPE = 'Content-Type'.freeze
          HEADER_CONTENT_TYPE_OCTET_STREAM = 'application/octet-stream'.freeze

          FORM_FIELD_PPROF_DATA = 'data[rubyprofile.pprof]'.freeze
          PPROF_DEFAULT_FILENAME = 'rubyprofile.pprof.gz'.freeze

          FORM_FIELD_CODE_PROVENANCE_DATA = 'data[code_provenance.json]'.freeze
          CODE_PROVENANCE_FILENAME = 'code_provenance.json.gz'.freeze
        end
      end
    end
  end
end
