require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sequel/configuration/settings'
require 'ddtrace/contrib/sequel/patcher'

module Datadog
  module Contrib
    module Sequel
      # Description of Sequel integration
      class Integration
        include Contrib::Integration

        register_as :sequel, auto_patch: false

        def self.version
          Gem.loaded_specs['sequel'] && Gem.loaded_specs['sequel'].version
        end

        def self.present?
          super && defined?(::Sequel)
        end

        def self.compatible?
          super && Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new('2.0.0')
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
