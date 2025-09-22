# frozen_string_literal: true

require_relative '../middleware'
require_relative '../events'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        module Instrumentation
          # Instrumentation for WaterDrop::Producer
          module Producer
            def self.prepended(base)
              base.class_eval do
                # Track if we've already set up instrumentation for this producer
                attr_accessor :_datadog_instrumented
              end
            end

            # Override the setup method to add our middleware and event subscription
            def setup(&block)
              puts "🔍 [WATERDROP PRODUCER] Setup called"
              result = super(&block)

              # Only instrument once per producer instance
              if _datadog_instrumented
                puts "🔍 [WATERDROP PRODUCER] Already instrumented, skipping"
                return result
              end

              puts "🔍 [WATERDROP PRODUCER] Adding middleware and event subscription"
              # Add our middleware for DSM header injection
              middleware.append(Middleware.new)

              # Subscribe to production events for span creation
              Events.subscribe!(self)

              # Mark as instrumented
              self._datadog_instrumented = true
              puts "🔍 [WATERDROP PRODUCER] Instrumentation complete"

              result
            end
          end
        end
      end
    end
  end
end
