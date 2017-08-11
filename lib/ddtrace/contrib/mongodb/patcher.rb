# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module MongoDB
      APP = 'mongodb'
      SERVICE = 'mongodb'.freeze

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
              require 'ddtrace/pin'
              require 'ddtrace/ext/net'
              require 'ddtrace/ext/mongo'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/mongodb/parsers'
              require 'ddtrace/contrib/mongodb/subscribers'

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
            Datadog::Contrib::MongoDB::MongoCommandSubscriber.new
          )
        end

        def patch_mongo_client
          ::Mongo::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Monkey.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              # attach the Pin instance
              initialize_without_datadog(*args)
              pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              if pin.tracer && pin.service
                pin.tracer.set_service_info(pin.service, 'mongodb', pin.app_type)
              end
            end

            def datadog_pin
              # safe-navigation to avoid crashes during each query
              return unless self.respond_to? :cluster
              return unless self.cluster.respond_to? :addresses
              return unless self.cluster.addresses.respond_to? :first
              Datadog::Pin.get_from(self.cluster.addresses.first)
            end

            def datadog_pin=(pin)
              # safe-navigation to avoid crashes during each query
              return unless self.respond_to? :cluster
              return unless self.cluster.respond_to? :addresses
              return unless self.cluster.addresses.respond_to? :each
              # attach the PIN to all cluster addresses. One of them is used
              # when executing a Command and it is attached to the Monitoring
              # Event instance.
              self.cluster.addresses.each { |x| pin.onto(x) }
            end
          end
        end
      end
    end
  end
end
