# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/resque/configuration/settings'
require 'datadog/tracing/contrib/resque/patcher'

module Datadog
  module Tracing
    module Contrib
      module Resque
        # Description of Resque integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :resque, auto_patch: true

          def self.version
            Gem.loaded_specs['resque'] && Gem.loaded_specs['resque'].version
          end

          def self.loaded?
            !defined?(::Resque).nil?
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

          class << self
            # Globally-acccesible reference for pre-forking optimization
            attr_accessor :sync_writer
          end
        end
      end
    end
  end
end
