require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/concurrent_ruby/patcher'
require 'ddtrace/contrib/concurrent_ruby/configuration/settings'

module Datadog
  module Contrib
    module ConcurrentRuby
      # Describes the ConcurrentRuby integration
      class Integration
        include Contrib::Integration

        register_as :concurrent_ruby

        def self.version
          Gem.loaded_specs['concurrent-ruby'] && Gem.loaded_specs['concurrent-ruby'].version
        end

        def self.present?
          super && defined?(::Concurrent::Future)
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
