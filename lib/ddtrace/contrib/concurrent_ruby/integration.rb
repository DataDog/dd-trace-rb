require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/concurrent_ruby/patcher'
require 'ddtrace/contrib/concurrent_ruby/configuration/settings'

module Datadog
  module Contrib
    module ConcurrentRuby
      # Propagate Tracing context in Concurrent::Future
      class Integration
        include Contrib::Integration

        register_as :concurrent_ruby

        def self.compatible?
          defined?(::Concurrent::Future)
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
