require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/gc/configuration/settings'
require 'ddtrace/contrib/gc/patcher'

module Datadog
  module Contrib
    module GC
      class Integration
        include Contrib::Integration

        register_as :gc

        def self.version
          Gem::Version.new('1.0.0')
        end

        def self.present?
          super && !!::Datadog::Runtime.current
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
