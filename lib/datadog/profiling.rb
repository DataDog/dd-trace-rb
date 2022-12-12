# typed: true

require_relative 'core'
require_relative 'core/environment/variable_helpers'
require_relative 'core/utils/only_once'

module Datadog
  # Contains profiler for generating stack profiles, etc.
  module Profiling
    GOOGLE_PROTOBUF_MINIMUM_VERSION = Gem::Version.new('3.0')
    private_constant :GOOGLE_PROTOBUF_MINIMUM_VERSION

    def self.supported?
      unsupported_reason.nil?
    end

    def self.unsupported_reason
      # NOTE: Only the first matching reason is returned, so try to keep a nice order on reasons -- e.g. tell users
      # first that they can't use this on JRuby before telling them that they are missing protobuf

      native_library_compilation_skipped? ||
        native_library_failed_to_load? ||
        protobuf_gem_unavailable? ||
        protobuf_version_unsupported? ||
        protobuf_failed_to_load?
    end

    # Starts the profiler, if the profiler is supported by in
    # this runtime environment and if the profiler has been enabled
    # in configuration.
    #
    # @return [Boolean] `true` if the profiler has successfully started, otherwise `false`.
    # @public_api
    def self.start_if_enabled
      # If the profiler was not previously touched, getting the profiler instance triggers start as a side-effect
      # otherwise we get nil
      profiler = Datadog.send(:components).profiler
      # ...but we still try to start it BECAUSE if the process forks, the profiler will exist but may
      # not yet have been started in the fork
      profiler.start if profiler
      !!profiler
    end

    private_class_method def self.native_library_compilation_skipped?
      skipped_reason = try_reading_skipped_reason_file

      "Your ddtrace installation is missing support for the Continuous Profiler because #{skipped_reason}" if skipped_reason
    end

    private_class_method def self.try_reading_skipped_reason_file(file_api = File)
      # This file, if it exists, is recorded by extconf.rb during compilation of the native extension
      skipped_reason_file = "#{__dir__}/../../ext/ddtrace_profiling_native_extension/skipped_reason.txt"

      begin
        return unless file_api.exist?(skipped_reason_file)

        contents = file_api.read(skipped_reason_file).strip
        contents unless contents.empty?
      rescue StandardError
        # Do nothing
      end
    end

    private_class_method def self.protobuf_gem_unavailable?
      # NOTE: On environments where protobuf is already loaded, we skip the check. This allows us to support environments
      # where no Gem.loaded_version is NOT available but customers are able to load protobuf; see for instance
      # https://github.com/teamcapybara/capybara/commit/caf3bcd7664f4f2691d0ca9ef3be9a2a954fecfb
      if !defined?(::Google::Protobuf) && Gem.loaded_specs['google-protobuf'].nil?
        "Missing google-protobuf dependency; please add `gem 'google-protobuf', '~> 3.0'` to your Gemfile or gems.rb file"
      end
    end

    private_class_method def self.protobuf_version_unsupported?
      # See above for why we skip the check when protobuf is already loaded; note that when protobuf was already loaded
      # we skip the version check to avoid the call to Gem.loaded_specs. Unfortunately, protobuf does not seem to
      # expose the gem version constant elsewhere, so in that setup we are not able to check the version.
      if !defined?(::Google::Protobuf) && Gem.loaded_specs['google-protobuf'].version < GOOGLE_PROTOBUF_MINIMUM_VERSION
        'Your google-protobuf is too old; ensure that you have google-protobuf >= 3.0 by ' \
        "adding `gem 'google-protobuf', '~> 3.0'` to your Gemfile or gems.rb file"
      end
    end

    private_class_method def self.protobuf_failed_to_load?
      unless protobuf_loaded_successfully?
        'There was an error loading the google-protobuf library; see previous warning message for details'
      end
    end

    # The `google-protobuf` gem depends on a native component, and its creators helpfully tried to provide precompiled
    # versions of this extension on rubygems.org.
    #
    # Unfortunately, for a long time, the supported Ruby versions metadata on these precompiled versions of the extension
    # was not correctly set. (This is fixed in newer versions -- but not all Ruby versions we want to support can use
    # these.)
    #
    # Thus, the gem can still be installed, but can be in a broken state. To avoid breaking customer applications, we
    # use this helper to load it and gracefully handle failures.
    private_class_method def self.protobuf_loaded_successfully?
      return @protobuf_loaded if defined?(@protobuf_loaded)

      begin
        require 'google/protobuf'
        @protobuf_loaded = true
      rescue LoadError => e
        # NOTE: We use Kernel#warn here because this code gets run BEFORE Datadog.logger is actually set up.
        # In the future it'd be nice to shuffle the logger startup to happen first to avoid this special case.
        Kernel.warn(
          '[DDTRACE] Error while loading google-protobuf gem. ' \
          "Cause: '#{e.class.name} #{e.message}' Location: '#{Array(e.backtrace).first}'. " \
          'This can happen when google-protobuf is missing its native components. ' \
          'To fix this, try removing and reinstalling the gem, forcing it to recompile the components: ' \
          '`gem uninstall google-protobuf -a; BUNDLE_FORCE_RUBY_PLATFORM=true bundle install`. ' \
          'If the error persists, please contact Datadog support at <https://docs.datadoghq.com/help/>.'
        )
        @protobuf_loaded = false
      end
    end

    private_class_method def self.native_library_failed_to_load?
      success, exception = try_loading_native_library

      unless success
        if exception
          'There was an error loading the profiling native extension due to ' \
          "'#{exception.class.name} #{exception.message}' at '#{exception.backtrace.first}'"
        else
          'The profiling native extension did not load correctly. ' \
          'For help solving this issue, please contact Datadog support at <https://docs.datadoghq.com/help/>.' \
        end
      end
    end

    private_class_method def self.try_loading_native_library
      begin
        require_relative 'profiling/load_native_extension'

        success =
          defined?(Profiling::NativeExtension) && Profiling::NativeExtension.send(:native_working?)
        [success, nil]
      rescue StandardError, LoadError => e
        [false, e]
      end
    end

    private_class_method def self.load_profiling
      return false unless supported?

      require_relative 'profiling/ext/forking'
      require_relative 'profiling/collectors/code_provenance'
      require_relative 'profiling/collectors/cpu_and_wall_time'
      require_relative 'profiling/collectors/cpu_and_wall_time_worker'
      require_relative 'profiling/collectors/dynamic_sampling_rate'
      require_relative 'profiling/collectors/idle_sampling_helper'
      require_relative 'profiling/collectors/old_stack'
      require_relative 'profiling/collectors/stack'
      require_relative 'profiling/stack_recorder'
      require_relative 'profiling/old_recorder'
      require_relative 'profiling/exporter'
      require_relative 'profiling/scheduler'
      require_relative 'profiling/tasks/setup'
      require_relative 'profiling/profiler'
      require_relative 'profiling/native_extension'
      require_relative 'profiling/trace_identifiers/helper'
      require_relative 'profiling/pprof/pprof_pb'
      require_relative 'profiling/tag_builder'
      require_relative 'profiling/http_transport'

      true
    end

    load_profiling
  end
end
