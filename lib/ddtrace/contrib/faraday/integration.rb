require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/faraday/configuration/settings'
require 'ddtrace/contrib/faraday/patcher'

module Datadog
  module Contrib
    module Faraday
      # Description of Faraday integration
      class Integration
        include Contrib::Integration

        register_as :faraday, auto_patch: true

        def self.version
          Gem.loaded_specs['faraday'] && Gem.loaded_specs['faraday'].version
        end

        def self.present?
          super && defined?(::Faraday)
        end

        def self.compatible?
          super && version < Gem::Version.new('1.0.0')
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
