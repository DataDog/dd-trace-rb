require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/lograge/configuration/settings'
require 'ddtrace/contrib/lograge/patcher'

module Datadog
  module Contrib
    module Lograge
      # Description of Lograge integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.11.0')

        register_as :lograge

        def self.version
          Gem.loaded_specs['lograge'] && Gem.loaded_specs['lograge'].version
        end

        def self.loaded?
          !defined?(::Lograge::LogSubscribers::Base).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        # enabled by rails integration and has a hard dependancy on rails
        # so can safely say this shouldn't ever be part of auto instrumentation
        # https://github.com/roidrage/lograge/blob/1729eab7956bb95c5992e4adab251e4f93ff9280/lograge.gemspec#L18-L20
        def auto_instrument?
          false
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
