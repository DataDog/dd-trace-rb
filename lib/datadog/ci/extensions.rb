# typed: true
require 'datadog/core/configuration/settings'
require 'datadog/core/configuration/components'

require 'datadog/ci/configuration/settings'
require 'datadog/ci/configuration/components'

module Datadog
  module CI
    # Extends Datadog tracing with CI features
    module Extensions
      def self.activate!
        Datadog::Core::Configuration::Settings.extend(CI::Configuration::Settings)
        Datadog::Core::Configuration::Components.prepend(CI::Configuration::Components)
      end
    end
  end
end
