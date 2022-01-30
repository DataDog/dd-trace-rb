# typed: false
require 'ddtrace/contrib/active_record/configuration/resolver'
require 'ddtrace/contrib/active_record/configuration/settings'
require 'ddtrace/contrib/active_record/events'
require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rails/utils'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Describes the ActiveRecord integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :active_record, auto_patch: false

          def self.version
            Gem.loaded_specs['activerecord'] && Gem.loaded_specs['activerecord'].version
          end

          def self.loaded?
            !defined?(::ActiveRecord).nil?
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
            ActiveRecord::Patcher
          end

          def resolver
            @resolver ||= Configuration::Resolver.new
          end
        end
      end
    end
  end
end
