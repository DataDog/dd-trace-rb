# frozen_string_literal: true

module Datadog
  module Profiling
    module Ext
      ENV_ENABLED = 'DD_PROFILING_ENABLED'
      ENV_UPLOAD_TIMEOUT = 'DD_PROFILING_UPLOAD_TIMEOUT'
      ENV_MAX_FRAMES = 'DD_PROFILING_MAX_FRAMES'
      ENV_AGENTLESS = 'DD_PROFILING_AGENTLESS'
      ENV_ENDPOINT_COLLECTION_ENABLED = 'DD_PROFILING_ENDPOINT_COLLECTION_ENABLED'

      module Transport
        module HTTP
          FORM_FIELD_TAG_ENV = 'env'
          FORM_FIELD_TAG_HOST = 'host'
          FORM_FIELD_TAG_LANGUAGE = 'language'
          FORM_FIELD_TAG_PID = 'process_id'
          FORM_FIELD_TAG_PROFILER_VERSION = 'profiler_version'
          FORM_FIELD_TAG_RUNTIME = 'runtime'
          FORM_FIELD_TAG_RUNTIME_ENGINE = 'runtime_engine'
          FORM_FIELD_TAG_RUNTIME_ID = 'runtime-id'
          FORM_FIELD_TAG_RUNTIME_PLATFORM = 'runtime_platform'
          FORM_FIELD_TAG_RUNTIME_VERSION = 'runtime_version'
          FORM_FIELD_TAG_SERVICE = 'service'
          FORM_FIELD_TAG_VERSION = 'version'

          PPROF_DEFAULT_FILENAME = 'rubyprofile.pprof'
          CODE_PROVENANCE_FILENAME = 'code-provenance.json'
        end
      end
    end
  end
end
