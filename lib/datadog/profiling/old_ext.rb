# typed: true

module Datadog
  module Profiling
    # NOTE: This OldExt file is temporary and expected to be removed once the migration to the new `HttpTransport` class
    # is complete
    module OldExt
      module Transport
        module HTTP
          URI_TEMPLATE_DD_API = 'https://intake.profile.%s/'.freeze

          FORM_FIELD_RECORDING_START = 'start'.freeze
          FORM_FIELD_RECORDING_END = 'end'.freeze
          FORM_FIELD_FAMILY = 'family'.freeze
          FORM_FIELD_TAG_ENV = 'env'.freeze
          FORM_FIELD_TAG_HOST = 'host'.freeze
          FORM_FIELD_TAG_LANGUAGE = 'language'.freeze
          FORM_FIELD_TAG_PID = 'process_id'.freeze
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

          FORM_FIELD_CODE_PROVENANCE_DATA = 'data[code-provenance.json]'.freeze
          CODE_PROVENANCE_FILENAME = 'code-provenance.json.gz'.freeze
        end
      end
    end
  end
end
