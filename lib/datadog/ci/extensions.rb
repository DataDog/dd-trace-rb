require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

require 'datadog/ci/configuration/settings'
require 'datadog/ci/configuration/components'

module Datadog
  module CI
    # Extends Datadog tracing with CI features
    module Extensions
      def self.activate!
        Datadog::Configuration::Settings.extend(CI::Configuration::Settings)
        Datadog::Configuration::Components.prepend(CI::Configuration::Components)
      end
    end
  end
end
