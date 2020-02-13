require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_record/events'
require 'ddtrace/contrib/active_record/configuration/resolver'
require 'ddtrace/contrib/active_record/configuration/settings'
require 'ddtrace/contrib/active_record/patcher'

module Datadog
  module Contrib
    module ActiveRecord
      # Describes the ActiveRecord integration
      class Integration
        include Contrib::Integration

        register_as :active_record, auto_patch: false

        def self.version
          Gem.loaded_specs['activerecord'] && Gem.loaded_specs['activerecord'].version
        end

        def self.loaded?
          defined?(::ActiveRecord)
        end

        def self.compatible?
          super && version >= Gem::Version.new('3.0')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          ActiveRecord::Patcher
        end

        def resolver
          @resolver ||= Configuration::Resolver.new
        end
      end
    end
  end
end
