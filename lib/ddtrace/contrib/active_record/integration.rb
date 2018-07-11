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

        def self.compatible?
          super \
            && RUBY_VERSION >= '1.9.3' \
            && Gem.loaded_specs['activerecord'] \
            && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('3.0') \
            && defined?(::ActiveRecord)
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
