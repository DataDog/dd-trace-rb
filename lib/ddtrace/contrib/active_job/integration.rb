# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_job/configuration/settings'
require 'ddtrace/contrib/active_job/patcher'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Contrib
    module ActiveJob
      # Describes the ActiveJob integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('4.2')

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
          !Datadog::Contrib::Rails::Utils.railtie_supported?
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          ActiveJob::Patcher
        end
      end
    end
  end
end
