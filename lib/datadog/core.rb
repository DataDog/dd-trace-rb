module Datadog
  # Datadog core public API.
  #
  # The Datadog teams ensures that public methods in this module
  # only receive backwards compatible changes, and breaking changes
  # will only occur in new major versions releases.
  module Core
    class << self
      # TODO: should the logger be available publicly?
      # TODO: Are there any valid use cases for Datadog.logger.log(...)
      # TODO: from the host application?
      #
      # @public_api
      def logger
        Datadog.logger
      end

      # TODO: should the publicly exposed configuration be mutable?
      # @public_api
      def configuration
        Datadog.configuration
      end

      # Apply configuration changes to `ddtrace`. An example of a {.configure} call:
      # ```
      # Datadog.configure do |c|
      #   c.sampling.default_rate = 1.0
      #   c.use :aws
      #   c.use :rails
      #   c.use :sidekiq
      #   # c.diagnostics.debug = true # Enables debug output
      # end
      # ```
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
      # See {Datadog::Configuration::Settings} for all available options, defaults, and
      # available environment variables for configuration.
      #
      # @yieldparam [Datadog::Configuration::Settings] c the mutable configuration object
      # @public_api
      def configure(&block)
        Datadog.configure(&block)
      end
      ruby2_keywords :configure if respond_to?(:ruby2_keywords, true)
    end
  end
end
