require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rake/configuration/settings'
require 'ddtrace/contrib/rake/patcher'

module Datadog
  module Contrib
    module Rake
      # Description of Rake integration
      class Integration
        include Contrib::Integration

        register_as :rake

        def self.version
          Gem.loaded_specs['rake'] && Gem.loaded_specs['rake'].version
        end

        def self.present?
          super && defined?(::Rake)
        end

        def self.compatible?
          super && RUBY_VERSION >= '2.0.0'
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
