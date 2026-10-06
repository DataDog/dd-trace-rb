# frozen_string_literal: true

require_relative "../configuration/ext"

require_relative "ext"

module Datadog
  module Core
    module Metrics
      # Dependency facts about the dogstatsd-ruby gem: the installed
      # version, the version the tracer is compatible with, the dogstatsd
      # endpoint defaults, and whether the installed version supports the
      # single thread client option.
      #
      # The facts are uncached; each consumer resolves them at its own
      # cadence (once per client or emitter instance), so consuming them
      # never changes how often the gem environment is probed.
      module Dogstatsd
        module_function

        # The version of the dogstatsd-ruby gem visible to this process, or
        # nil when the gem is not installed.
        #
        # @return [Gem::Version, nil]
        def installed_version
          (defined?(Datadog::Statsd::VERSION) &&
            Datadog::Statsd::VERSION &&
            Gem::Version.new(Datadog::Statsd::VERSION)) ||
            Gem.loaded_specs["dogstatsd-ruby"]&.version
        end

        # Returns whether the given dogstatsd-ruby version can be used by
        # the tracer: at least 3.3.0, and outside the 5.0-5.2 range, which
        # has known issues with process forks and does not support the
        # single thread mode the tracer uses to avoid them.
        #
        # @param version [Gem::Version, nil]
        # @return [Boolean]
        def supported?(version)
          !version.nil? && version >= Gem::Version.new("3.3.0") &&
            !(version >= Gem::Version.new("5.0") && version < Gem::Version.new("5.3"))
        end

        # Returns whether the given dogstatsd-ruby version accepts the
        # single_thread client option. dogstatsd-ruby >= 5.0 creates a
        # background thread by default but does not handle forks correctly,
        # causing resource leaks; single_thread mode avoids the problem.
        # Versions >= 5.0 are still valuable, as they support transparent
        # batch metric submission, which reduces submission overhead.
        # Versions < 5.0 are always single-threaded and do not have the
        # option.
        #
        # @param version [Gem::Version]
        # @return [Boolean]
        def single_thread_supported?(version)
          version >= Gem::Version.new("5.2")
        end

        # Default dogstatsd listener host, read from the environment.
        #
        # @return [String]
        def default_hostname
          DATADOG_ENV.fetch(Configuration::Ext::Agent::ENV_DEFAULT_HOST, Ext::DEFAULT_HOST)
        end

        # Default dogstatsd listener port, read from the environment.
        #
        # @return [Integer]
        def default_port
          DATADOG_ENV.fetch(Configuration::Ext::Metrics::ENV_DEFAULT_PORT, Ext::DEFAULT_PORT).to_i
        end
      end
    end
  end
end
