# rubocop:disable
require 'ddtrace'

module Datadog
  module Tracing
    module Contrib
      module Kernel
        def require(name)
          just_loaded = super

          @@dd_instance.require(name) if just_loaded

          just_loaded
        end

        class Instance
          def initialize
            @on_require = {}
          end

          def require(name)
            if @on_require.include?(name)
              Datadog.logger.debug { "Gem '#{name}' loaded. Invoking callback." }

              @on_require[name].call
            end
          rescue => e
            Datadog.logger.debug do
              "Failed to execute callback for gem '#{name}': #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}"
            end
          end

          def on_require(gem, &block)
            @on_require[gem] = block
          end
        end

        @@dd_instance = Instance.new

        def self.on_require(gem, &block)
          @@dd_instance.on_require(gem, &block)
        end

        def self.patch!
          ::Kernel.prepend(self)
        end

        DD_PATCH_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new
        private_constant :DD_PATCH_ONLY_ONCE
      end
    end
  end
end

Datadog::Tracing::Contrib::Kernel.patch! # TODO: I think this stays here actually!

ENV['DD_TRACE_DEBUG'] = 'true'

# Setup
require 'ddtrace'

Datadog.configure do |c|
  c.tracing.instrument :faraday
end

require 'faraday'

# User application
Faraday.get('http://example.com')

# Tear down
Datadog.shutdown! # Ensure traces have been flushed

# rubocop:enable