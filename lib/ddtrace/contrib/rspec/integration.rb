require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rspec/configuration/settings'
require 'ddtrace/contrib/rspec/patcher'
require 'ddtrace/contrib/integration'

module Datadog
  module Contrib
    module RSpec
      # Description of RSpec integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.0.0')

        register_as :rspec, auto_patch: true

        def self.version
          Gem.loaded_specs['rspec'] \
            && Gem.loaded_specs['rspec'].version
        end

        def self.loaded?
          !defined?(::RSpec).nil? && !defined?(::RSpec::Core).nil? && \
            !defined?(::RSpec::Core::Example).nil? && !defined?(::RSpec::Core::ExampleGroup).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
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
