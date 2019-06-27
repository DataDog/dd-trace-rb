require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    attr_writer :configuration

    RUBY_19_DEPRECATION_WARNING = %(
      Support for Ruby versions < 2.0 in dd-trace-rb is DEPRECATED.
      Last version to support Ruby < 2.0 will be 0.26.x, which will only receive critical bugfixes to existing features.
      Support for Ruby versions < 2.0 will be REMOVED with version 0.27.0.).freeze

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target) if block_given?
      else
        PinSetup.new(target, opts).call
      end

      # Raise Ruby 1.9 deprecation warning, if necessary.
      raise_ruby_19_deprecation_warning!
    end

    # Helper methods
    def tracer
      configuration.tracer
    end

    def runtime_metrics
      tracer.writer.runtime_metrics
    end

    # TODO: Remove with version 0.27.0
    def raise_ruby_19_deprecation_warning!
      return unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0')

      require 'ddtrace/patcher'

      Datadog::Patcher.do_once(:ruby_19_deprecation_warning) do
        Datadog::Tracer.log.warn(RUBY_19_DEPRECATION_WARNING)
      end
    end
  end
end
