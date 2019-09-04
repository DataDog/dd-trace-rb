require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/ethon/configuration/settings'
require 'ddtrace/contrib/ethon/patcher'

module Datadog
  module Contrib
    module Ethon
      # Description of Ethon integration
      class Integration
        include Contrib::Integration
        register_as :ethon

        def self.version
          Gem.loaded_specs['ethon'] && Gem.loaded_specs['ethon'].version
        end

        def self.present?
          super && defined?(::Ethon::Easy)
        end

        def self.compatible?
          super && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')
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
