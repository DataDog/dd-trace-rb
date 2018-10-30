require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/mysql2/ext'

module Datadog
  module Contrib
    module Mysql2
      # Mysql2::Client patch module
      module Client
        module_function

        def included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :aliased_query, :query
              remove_method :query
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Mysql2::Client patch 1.9.3 instance methods
        module InstanceMethodsCompatibility
          def query(*args)
            aliased_query(*args)
          end
        end

        # Mysql2::Client patch instance methods
        module InstanceMethods
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            include InstanceMethodsCompatibility
          end

          def query(sql, options = {})
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag(Ext::TAG_DB_NAME, query_options[:database])
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, query_options[:host])
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, query_options[:port])
              super(sql, options)
            end
          end

          def datadog_pin
            @datadog_pin ||= Datadog::Pin.new(
              Datadog.configuration[:mysql2][:service_name],
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::DB,
              tracer: Datadog.configuration[:mysql2][:tracer]
            )
          end
        end
      end
    end
  end
end
