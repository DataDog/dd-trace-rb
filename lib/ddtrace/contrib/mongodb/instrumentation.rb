require 'ddtrace/pin'
require 'ddtrace/ext/net'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/mongodb/ext'
require 'ddtrace/contrib/mongodb/parsers'
require 'ddtrace/contrib/mongodb/subscribers'

module Datadog
  module Contrib
    module MongoDB
      # Instrumentation for Mongo::Client
      module Instrumentation
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              # Instance methods
              include InstanceMethodsCompatibility
              include CommonInstanceMethods
              include ClientInstanceMethods if base == Mongo::Client
            end
          else
            base.send(:prepend, CommonInstanceMethods)
            base.send(:prepend, ClientInstanceMethods) if base == Mongo::Client
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def self.included(base)
            base.class_eval do
              alias_method :initialize_without_datadog, :initialize
              remove_method :initialize
            end
          end

          def initialize(*args, &block)
            initialize_without_datadog(*args, &block)
          end
        end

        # CommonInstanceMethods - implementing instrumentation
        module CommonInstanceMethods
          def initialize(*args, &blk)
            # attach the Pin instance
            super(*args, &blk)
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
        end

        # ClientInstanceMethods - implementing instrumentation
        module ClientInstanceMethods
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
