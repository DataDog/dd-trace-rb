# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module MongoDB
      APP = 'mongodb'
      SERVICE = 'mongodb'.freeze

      # `MongoCommandSubscriber` listens to all events from the `Monitoring`
      # system available in the Mongo driver.
      class MongoCommandSubscriber
        def initialize
          # keeps track of active Spans so that they can be retrieved
          # between executions. This data structure must be thread-safe.
          # TODO: add thread-safety
          @active_spans = {}
        end

        def started(event)
          # TODO: start a trace
        end

        def failed(event)
          # TODO: find the error? at least flag it as error
          finished(event)
        end

        def succeeded(event)
          finished(event)
        end

        def finished(event)
          # TODO: end the trace
        end
      end

      # Patcher adds subscribers to the MongoDB driver so that each command is traced.
      # Use the `Datadog::Monkey.patch_module(:mongodb)` to activate tracing for
      # this module.
      module Patcher
        @patched = false

        module_function

        def patched?
          @patched
        end

        def patch
          # TODO[manu] find the lowest supported version
          if !@patched && (defined?(::Mongo::Monitoring::Global) && \
                  Gem::Version.new(::Mongo::VERSION) >= Gem::Version.new('2.4.3'))
            begin
              require 'ddtrace/monkey'
              require 'ddtrace/pin'
              require 'ddtrace/ext/app_types'

              patch_mongo_client()
              add_mongo_monitoring()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply MongoDB integration: #{e}")
            end
          end
          @patched
        end

        def add_mongo_monitoring
          # Subscribe to all COMMAND queries with our subscriber class
          ::Mongo::Monitoring::Global.subscribe(
            ::Mongo::Monitoring::COMMAND,
            MongoComandSubscriber.new
          )
        end

        def patch_mongo_client
          ::Mongo::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Monkey.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            def datadog_pin
              # safe navigation to avoid NoMethodError; since all addresses
              # share the same PIN, returning the first one is enough
              address = self.try(:cluster).try(:addresses).try(:first)
              return unless address != nil
              Datadog::Pin.get_from(address)
            end

            def datadog_pin=
              # attach the PIN to all cluster addresses. One of them is used
              # when executing a Command and it is attached to the Monitoring
              # Event instance.
              addresses = self.try(:cluster).try(:addresses)
              return unless addresses.respond_to? :each
              addresses.each { |x| onto(x) }
            end
          end
        end
      end
    end
  end
end
