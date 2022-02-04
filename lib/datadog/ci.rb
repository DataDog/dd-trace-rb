# typed: false
require 'datadog/core'
require 'datadog/tracing'
require 'datadog/ci/configuration/validation_proxy'

module Datadog
  # Namespace for Datadog CI instrumentation:
  # e.g. rspec, cucumber, etc...
  module CI
    # Current CI configuration.
    #
    # Access to non-CI configuration will raise an error.
    #
    # To modify the configuration, use {.configure}.
    #
    # @return [Datadog::Core::Configuration::Settings]
    # @!attribute [r] configuration
    # @public_api

    # Apply configuration changes to `Datadog::CI`. An example of a {.configure} call:
    # ```
    # Datadog::CI.configure do |c|
    #   c.ci_mode.enabled = true
    # end
    # ```
    # See {Datadog::Core::Configuration::Settings} for all available options, defaults, and
    # available environment variables for configuration.
    #
    # Only permits access to CI configuration settings; others will raise an error.
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
  end
end

# Integrations
require 'datadog/ci/contrib/cucumber/integration'
require 'datadog/ci/contrib/rspec/integration'

# Extensions
require 'datadog/ci/extensions'
Datadog::CI::Extensions.activate!
