require_relative 'configuration/settings'
require_relative 'patcher'
require_relative '../integration'
require_relative '../rails/utils'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Describes the ActiveJob integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('4.2')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :active_job, auto_patch: false

          def self.version
            Gem.loaded_specs['activejob'] && Gem.loaded_specs['activejob'].version
          end

          def self.loaded?
            !defined?(::ActiveJob).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          # enabled by rails integration so should only auto instrument
          # if detected that it is being used without rails
          def auto_instrument?
            !Contrib::Rails::Utils.railtie_supported?
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            ActiveJob::Patcher
          end
        end
      end
    end
  end
end
