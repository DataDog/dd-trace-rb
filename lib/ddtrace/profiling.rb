module Datadog
  # Contains profiler for generating stack profiles, etc.
  module Profiling
    module_function

    GOOGLE_PROTOBUF_MINIMUM_VERSION = Gem::Version.new('3.0')

    def supported?
      google_protobuf_supported?
    end

    def google_protobuf_supported?
      RUBY_PLATFORM != 'java' \
        && !Gem.loaded_specs['google-protobuf'].nil? \
        && Gem.loaded_specs['google-protobuf'].version >= GOOGLE_PROTOBUF_MINIMUM_VERSION
    end

    def load_profiling
      require 'ddtrace/profiling/collectors/stack'
      require 'ddtrace/profiling/exporter'
      require 'ddtrace/profiling/recorder'
      require 'ddtrace/profiling/scheduler'
      require 'ddtrace/profiling/transport/io'

      require 'ddtrace/profiling/pprof/pprof_pb' if google_protobuf_supported?
    end

    load_profiling if supported?
  end
end
