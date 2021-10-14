require 'datadog/security'
require 'datadog/security/reactive/engine'

module Datadog
  module Security
    module Reactive
      class Operation
        attr_reader :reactive
        attr_reader :parent
        attr_reader :name

        def initialize(name, parent = nil, reactive_engine = nil)
          Datadog.logger.debug { "operation: #{name} initialize" }
          @name = name
          @parent = parent
          @reactive = reactive_engine || parent && parent.reactive || Reactive::Engine.new

          # TODO: concurrent store
          # TODO: constant
          Thread.current[:datadog_security_active_operation] = self

          yield self if block_given?
        ensure
          finalize
        end

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
