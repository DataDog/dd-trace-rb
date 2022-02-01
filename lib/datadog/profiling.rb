# typed: true
require 'datadog/core'
require 'datadog/core/environment/variable_helpers'
require 'datadog/core/utils/only_once'
require 'datadog/profiling/configuration/validation_proxy'

module Datadog
  # Contains profiler for generating stack profiles, etc.
  module Profiling # rubocop:disable Metrics/ModuleLength
    GOOGLE_PROTOBUF_MINIMUM_VERSION = Gem::Version.new('3.0')
    private_constant :GOOGLE_PROTOBUF_MINIMUM_VERSION

    SKIPPED_NATIVE_EXTENSION_ONLY_ONCE = Core::Utils::OnlyOnce.new
    private_constant :SKIPPED_NATIVE_EXTENSION_ONLY_ONCE

    def self.supported?
      unsupported_reason.nil?
    end

    def self.unsupported_reason
      # NOTE: Only the first matching reason is returned, so try to keep a nice order on reasons -- e.g. tell users
      # first that they can't use this on JRuby before telling them that they are missing protobuf

      ruby_engine_unsupported? ||
        native_library_failed_to_load? ||
        protobuf_gem_unavailable? ||
        protobuf_version_unsupported? ||
        protobuf_failed_to_load?
    end

    # Apply configuration changes to `Datadog::Profiling`. An example of a {.configure} call:
    # ```
    # Datadog::Profiling.configure do |c|
    #   c.profiling.enabled = true
    # end
    # ```
    # See {Datadog::Core::Configuration::Settings} for all available options, defaults, and
    # available environment variables for configuration.
    #
    # Only permits access to profiling configuration settings; others will raise an error.
    # If you wish to configure a global setting, use `Datadog.configure`` instead.
    # If you wish to configure a setting for a specific Datadog component (e.g. Tracing),
    # use the corresponding `Datadog::COMPONENT.configure` method instead.
    #
    # Because many configuration changes require restarting internal components,
    # invoking {.configure} is the only safe way to change `ddtrace` configuration.
    #
    # Successive calls to {.configure} maintain the previous configuration values:
    # configuration is additive between {.configure} calls.
    #
    # The yielded configuration `c` comes pre-populated from environment variables, if
    # any are applicable.
    #
    # See {Datadog::Core::Configuration::Settings} for all available options, defaults, and
    # available environment variables for configuration.
    #
    # Will raise errors if invalid setting is accessed.
    #
    # @yieldparam [Datadog::Core::Configuration::Settings] c the mutable configuration object
    # @return [void]
    # @public_api
    def self.configure
      # Wrap block with profiling option validation
      wrapped_block = proc do |c|
        yield(Configuration::ValidationProxy.new(c))
      end

      # Configure application normally
      Datadog.send(:internal_configure, &wrapped_block)
    end

    # Current profiler configuration.
    #
    # Access to non-profiling configuration will raise an error.
    #
    # To modify the configuration, use {.configure}.
    #
    # @return [Datadog::Core::Configuration::Settings]
    # @!attribute [r] configuration
    # @public_api
    def self.configuration
      Configuration::ValidationProxy.new(
        Datadog.send(:internal_configuration)
      )
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

    private_class_method def self.ruby_engine_unsupported?
      'JRuby is not supported' if RUBY_ENGINE == 'jruby'
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
          "Cause: '#{e.message}' Location: '#{Array(e.backtrace).first}'. " \
          'This can happen when google-protobuf is missing its native components. ' \
          'To fix this, try removing and reinstalling the gem, forcing it to recompile the components: ' \
          '`gem uninstall google-protobuf -a; BUNDLE_FORCE_RUBY_PLATFORM=true bundle install`. ' \
          'If the error persists, please contact support via <https://docs.datadoghq.com/help/> or ' \
          'file a bug at <https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug>.'
        )
        @protobuf_loaded = false
      end
    end

    private_class_method def self.native_library_failed_to_load?
      success, exception = try_loading_native_library

      unless success
        if exception
          'There was an error loading the profiling native extension due to ' \
          "'#{exception.message}' at '#{exception.backtrace.first}'"
        else
          'The profiling native extension did not load correctly. ' \
          'If the error persists, please contact support via <https://docs.datadoghq.com/help/> or ' \
          'file a bug at <https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug>.'
        end
      end
    end

    private_class_method def self.try_loading_native_library
      if Core::Environment::VariableHelpers.env_to_bool('DD_PROFILING_NO_EXTENSION', false)
        SKIPPED_NATIVE_EXTENSION_ONLY_ONCE.run do
          Kernel.warn(
            '[DDTRACE] Skipped loading of profiling native extension due to DD_PROFILING_NO_EXTENSION environment ' \
            'variable being set. ' \
            'This option is experimental and will lead to the profiler not working in future releases. ' \
            'If you needed to use this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>.'
          )
        end

        return [true, nil]
      end

      begin
        require "ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
        success =
          defined?(Profiling::NativeExtension) && Profiling::NativeExtension.send(:native_working?)
        [success, nil]
      rescue StandardError, LoadError => e
        [false, e]
      end
    end

    private_class_method def self.load_profiling
      return false unless supported?

      require 'datadog/profiling/ext/forking'
      require 'datadog/profiling/collectors/code_provenance'
      require 'datadog/profiling/collectors/stack'
      require 'datadog/profiling/exporter'
      require 'datadog/profiling/recorder'
      require 'datadog/profiling/scheduler'
      require 'datadog/profiling/tasks/setup'
      require 'datadog/profiling/transport/io'
      require 'datadog/profiling/transport/http'
      require 'datadog/profiling/profiler'
      require 'datadog/profiling/native_extension'
      require 'datadog/profiling/trace_identifiers/helper'
      require 'datadog/profiling/pprof/pprof_pb'

      true
    end

    load_profiling if supported?
  end
end
