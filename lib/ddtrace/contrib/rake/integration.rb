# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rake/configuration/settings'
require 'ddtrace/contrib/rake/patcher'

module Datadog
  module Contrib
    module Rake
      # Description of Rake integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('12.0')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :rake

        def self.version
          Gem.loaded_specs['rake'] && Gem.loaded_specs['rake'].version
        end

        def self.loaded?
          !defined?(::Rake::Task).nil?
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
