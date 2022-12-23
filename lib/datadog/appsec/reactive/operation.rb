# typed: ignore

require_relative 'engine'

module Datadog
  module AppSec
    module Reactive
      # Reactive Engine nested operation tracking
      class Operation
        attr_reader :reactive,
          :parent,
          :name

        def initialize(name, parent = nil, reactive_engine = nil)
          Datadog.logger.debug { "operation: #{name} initialize" }
          @name = name
          @parent = parent
          @reactive = reactive_engine || (parent.reactive unless parent.nil?) || Reactive::Engine.new

          # TODO: concurrent store
          # TODO: constant
          Thread.current[:datadog_security_active_operation] = self

          yield self if block_given?
        ensure
          finalize
        end

        # TODO: use structs instead of an arg splat
        def subscribe(*addresses, &block)
          reactive.subscribe(*addresses, &block)
        end

        def publish(address, data)
          reactive.publish(address, data)
        end

        def finalize
          Datadog.logger.debug { "operation: #{name} finalize" }
          Thread.current[:datadog_security_active_operation] = parent
        end

        class << self
          def active
            Thread.current[:datadog_security_active_operation]
          end
        end
      end
    end
  end
end
