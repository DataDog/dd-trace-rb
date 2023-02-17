# typed: ignore

require_relative '../integration'

require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module AppSec
    module Contrib
      module Internal
        # Description of Rack integration
        class Integration
          include ::Datadog::AppSec::Contrib::Integration

          register_as :datadog, auto_patch: true

          def self.available?
            true
          end

          def self.loaded?
            true
          end

          def self.compatible?
            true
          end

          def self.auto_instrument?
            true
          end

          def default_configuration
            # Do we need that?
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end
        end
      end
    end
  end
end
