module Datadog
  # Contains profiler for generating stack profiles, etc.
  module Profiling
    module_function

    GOOGLE_PROTOBUF_MINIMUM_VERSION = Gem::Version.new('3.0')
    private_constant :GOOGLE_PROTOBUF_MINIMUM_VERSION

    def supported?
      unsupported_reason.nil?
    end

    def unsupported_reason
      # NOTE: Only the first matching reason is returned, so try to keep a nice order on reasons -- e.g. tell users
      # first that they can't use this on JRuby before telling them that they are missing protobuf

      ruby_engine_unsupported? || protobuf_gem_unavailable? || protobuf_version_unsupported? || protobuf_failed_to_load?
    end

    def self.ruby_engine_unsupported?
      'JRuby is not supported' if RUBY_ENGINE == 'jruby'
    end
    private_class_method :ruby_engine_unsupported?

    def self.protobuf_gem_unavailable?
      # NOTE: On environments where protobuf is already loaded, we skip the check. This allows us to support environments
      # where no Gem.loaded_version is NOT available but customers are able to load protobuf; see for instance
      # https://github.com/teamcapybara/capybara/commit/caf3bcd7664f4f2691d0ca9ef3be9a2a954fecfb
      if !defined?(::Google::Protobuf) && Gem.loaded_specs['google-protobuf'].nil?
        "Missing google-protobuf dependency; please add `gem 'google-protobuf', '~> 3.0'` to your Gemfile or gems.rb file"
      end
    end
    private_class_method :protobuf_gem_unavailable?

    def self.protobuf_version_unsupported?
      # See above for why we skip the check when protobuf is already loaded; note that when protobuf was already loaded
      # we skip the version check to avoid the call to Gem.loaded_specs. Unfortunately, protobuf does not seem to
      # expose the gem version constant elsewhere, so in that setup we are not able to check the version.
      if !defined?(::Google::Protobuf) && Gem.loaded_specs['google-protobuf'].version < GOOGLE_PROTOBUF_MINIMUM_VERSION
        'Your google-protobuf is too old; ensure that you have google-protobuf >= 3.0 by ' \
        "adding `gem 'google-protobuf', '~> 3.0'` to your Gemfile or gems.rb file"
      end
    end
    private_class_method :protobuf_version_unsupported?

    def self.protobuf_failed_to_load?
      unless protobuf_loaded_successfully?
        'There was an error loading the google-protobuf library; see previous warning message for details'
      end
    end
    private_class_method :protobuf_failed_to_load?

    # The `google-protobuf` gem depends on a native component, and its creators helpfully tried to provide precompiled
    # versions of this extension on rubygems.org.
    #
    # Unfortunately, for a long time, the supported Ruby versions metadata on these precompiled versions of the extension
    # was not correctly set. (This is fixed in newer versions -- but not all Ruby versions we want to support can use
    # these.)
    #
    # Thus, the gem can still be installed, but can be in a broken state. To avoid breaking customer applications, we
    # use this helper to load it and gracefully handle failures.
    def self.protobuf_loaded_successfully?
      return @protobuf_loaded if defined?(@protobuf_loaded)

      begin
        require 'google/protobuf'
        @protobuf_loaded = true
      rescue LoadError => e
        # NOTE: We use Kernel#warn here because this code gets run BEFORE Datadog.logger is actually set up.
        # In the future it'd be nice to shuffle the logger startup to happen first to avoid this special case.
        Kernel.warn(
          "[DDTRACE] Error while loading google-protobuf gem. Cause: '#{e.message}' Location: '#{e.backtrace.first}'. " \
          'This can happen when google-protobuf is missing its native components. ' \
          'To fix this, try removing and reinstalling the gem, forcing it to recompile the components: ' \
          '`gem uninstall google-protobuf -a; BUNDLE_FORCE_RUBY_PLATFORM=true bundle install`. ' \
          'If the error persists, please contact support via <https://docs.datadoghq.com/help/> or ' \
          'file a bug at <https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug>.'
        )
        @protobuf_loaded = false
      end
    end
    private_class_method :protobuf_loaded_successfully?

    def self.load_profiling
      return false unless supported?

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

      require 'ddtrace/profiling/pprof/pprof_pb'

      true
    end
    private_class_method :load_profiling

    load_profiling if supported?
  end
end
