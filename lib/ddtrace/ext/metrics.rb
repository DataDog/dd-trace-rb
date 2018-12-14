module Datadog
  module Ext
    module Metrics
      TAG_DATA_TYPE = 'datadog.tracer.data_type'.freeze
      TAG_DATA_TYPE_SERVICES = "#{TAG_DATA_TYPE}:services".freeze
      TAG_DATA_TYPE_TRACES = "#{TAG_DATA_TYPE}:traces".freeze
      TAG_ENCODING_TYPE = 'datadog.tracer.encoding_type'.freeze
      TAG_LANG = 'datadog.tracer.lang'.freeze
      TAG_LANG_INTERPRETER = 'datadog.tracer.lang_interpreter'.freeze
      TAG_LANG_VERSION = 'datadog.tracer.lang_version'.freeze
      TAG_PRIORITY_SAMPLING = 'datadog.tracer.priority_sampling'.freeze
      TAG_PRIORITY_SAMPLING_DISABLED = "#{TAG_PRIORITY_SAMPLING}:false".freeze
      TAG_PRIORITY_SAMPLING_ENABLED = "#{TAG_PRIORITY_SAMPLING}:true".freeze
      TAG_TRACER_VERSION = 'datadog.tracer.version'.freeze
    end
  end
end
