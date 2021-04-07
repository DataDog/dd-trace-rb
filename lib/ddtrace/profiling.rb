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
        && Gem.loaded_specs['google-protobuf'].version >= GOOGLE_PROTOBUF_MINIMUM_VERSION \
        && !defined?(@failed_to_load_protobuf)
    end

    def load_profiling
      require 'ddtrace/profiling/ext/cpu'
      require 'ddtrace/profiling/ext/forking'

      require 'ddtrace/profiling/collectors/stack'
      require 'ddtrace/profiling/exporter'
      require 'ddtrace/profiling/recorder'
      require 'ddtrace/profiling/scheduler'
      require 'ddtrace/profiling/tasks/setup'
      require 'ddtrace/profiling/transport/io'
      require 'ddtrace/profiling/transport/http'
      require 'ddtrace/profiling/profiler'

      begin
        require 'ddtrace/profiling/pprof/pprof_pb' if google_protobuf_supported?
      rescue LoadError => e
        @failed_to_load_protobuf = true
        Kernel.warn(
          "[DDTRACE] Error while loading google-protobuf gem. Cause: '#{e.message}' Location: '#{e.backtrace.first}'. " \
          'This can happen when google-protobuf is missing its native components. ' \
          'To fix this, try removing and reinstalling the gem, forcing it to recompile the components: ' \
          '`gem uninstall google-protobuf -a; BUNDLE_FORCE_RUBY_PLATFORM=true bundle install`. ' \
          'If the error persists, please contact support via <https://docs.datadoghq.com/help/> or ' \
          'file a bug at <https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug>.'
        )
      end
    end

    load_profiling if supported?
  end
end
