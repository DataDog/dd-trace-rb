# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/pg/configuration/settings'
require 'datadog/tracing/contrib/pg/patcher'

module Datadog
  module Tracing
    module Contrib
      module Pg
        # Description of pg integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('0.18.4')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :pg

          def self.version
            Gem.loaded_specs['pg'] && Gem.loaded_specs['pg'].version
          end

          def self.loaded?
            !defined?(::PG).nil?
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
