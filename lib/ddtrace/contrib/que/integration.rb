# typed: false
# frozen_string_literal: true

require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/que/ext'
require 'ddtrace/contrib/que/configuration/settings'
require 'ddtrace/contrib/que/patcher'

module Datadog
  module Tracing
    module Contrib
      module Que
        # Description of Que integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.0.0.beta2')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :que, auto_patch: true

          def self.version
            Gem.loaded_specs['que'] && Gem.loaded_specs['que'].version
          end

          def self.loaded?
            !defined?(::Que).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
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
