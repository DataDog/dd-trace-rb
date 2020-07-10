module Datadog
  # Contains profiler for generating stack profiles, etc.
  module Profiling
    module_function

    FFI_MINIMUM_VERSION = Gem::Version.new('1.0')
    GOOGLE_PROTOBUF_MINIMUM_VERSION = Gem::Version.new('3.0')

    def supported?
      google_protobuf_supported?
    end

    def native_cpu_time_supported?
      RUBY_PLATFORM != 'java' \
        && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1') \
        && !Gem.loaded_specs['ffi'].nil? \
        && Gem.loaded_specs['ffi'].version >= FFI_MINIMUM_VERSION
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
      require 'ddtrace/profiling/tasks/setup'
      require 'ddtrace/profiling/transport/io'
      require 'ddtrace/profiling/profiler'

      require 'ddtrace/profiling/pprof/pprof_pb' if google_protobuf_supported?
    end

    load_profiling if supported?
  end
end
