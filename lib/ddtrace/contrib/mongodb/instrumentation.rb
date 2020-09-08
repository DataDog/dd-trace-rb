require 'ddtrace/pin'
require 'ddtrace/ext/net'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/mongodb/ext'
require 'ddtrace/contrib/mongodb/parsers'
require 'ddtrace/contrib/mongodb/subscribers'

module Datadog
  module Contrib
    module MongoDB
      # Instrumentation for Mongo integration
      module Instrumentation
        # Instrumentation for Mongo::Client
        module Client
          def self.included(base)
            base.send(:include, InstanceMethods)
          end

          # Instance methods for Mongo::Client
          module InstanceMethods
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

        # Instrumentation for Mongo::Address
        module Address
          def self.included(base)
            base.send(:include, InstanceMethods)
          end

          # Instance methods for Mongo::Address
          module InstanceMethods
            def datadog_pin
              @datadog_pin ||= begin
                service = Datadog.configuration[:mongo][:service_name]

                Datadog::Pin.new(
                  service,
                  app: Datadog::Contrib::MongoDB::Ext::APP,
                  app_type: Datadog::Ext::AppTypes::DB,
                  tracer: -> { Datadog.configuration[:mongo][:tracer] }
                )
              end
            end
          end
        end
      end
    end
  end
end
