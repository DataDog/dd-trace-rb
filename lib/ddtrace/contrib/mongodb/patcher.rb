require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/mongodb/ext'

module Datadog
  module Contrib
    module MongoDB
      # Patcher enables patching of 'mongo' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:mongo)
        end

        def patch
          do_once(:mongo) do
            begin
              require 'ddtrace/pin'
              require 'ddtrace/ext/net'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/mongodb/ext'
              require 'ddtrace/contrib/mongodb/parsers'
              require 'ddtrace/contrib/mongodb/subscribers'

              patch_mongo_client
              add_mongo_monitoring
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply MongoDB integration: #{e}")
            end
          end
        end

        def add_mongo_monitoring
          # Subscribe to all COMMAND queries with our subscriber class
          ::Mongo::Monitoring::Global.subscribe(::Mongo::Monitoring::COMMAND, MongoCommandSubscriber.new)
        end

        def patch_mongo_client
          ::Mongo::Client.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args, &blk)
              # attach the Pin instance
              initialize_without_datadog(*args, &blk)
              tracer = Datadog.configuration[:mongo][:tracer]
              service = Datadog.configuration[:mongo][:service_name]
              pin = Datadog::Pin.new(
                service,
                app: Datadog::Contrib::MongoDB::Ext::APP,
                app_type: Datadog::Ext::AppTypes::DB,
                tracer: tracer
              )
              pin.onto(self)
            end

            def datadog_pin
              # safe-navigation to avoid crashes during each query
              return unless respond_to? :cluster
              return unless cluster.respond_to? :addresses
              return unless cluster.addresses.respond_to? :first
              Datadog::Pin.get_from(cluster.addresses.first)
            end

            def datadog_pin=(pin)
              # safe-navigation to avoid crashes during each query
              return unless respond_to? :cluster
              return unless cluster.respond_to? :addresses
              return unless cluster.addresses.respond_to? :each
              # attach the PIN to all cluster addresses. One of them is used
              # when executing a Command and it is attached to the Monitoring
              # Event instance.
              cluster.addresses.each { |x| pin.onto(x) }
            end
          end
        end
      end
    end
  end
end
