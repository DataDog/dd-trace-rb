require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/mysql2/ext'

module Datadog
  module Contrib
    module Mysql2
      # Mysql2::Client patch module
      module Instrumentation
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              # Instance methods
              include InstanceMethodsCompatibility
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Mysql2::Client patch 1.9.3 instance methods
        module InstanceMethodsCompatibility
          def self.included(base)
            base.class_eval do
              alias_method :query_without_datadog, :query
              remove_method :query
            end
          end

          def query(*args, &block)
            query_without_datadog(*args, &block)
          end
        end

        # Mysql2::Client patch instance methods
        module InstanceMethods
          def query(sql, options = {})
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

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

          private

          def datadog_configuration
            Datadog.configuration[:mysql2]
          end

          def analytics_enabled?
            datadog_configuration[:analytics_enabled]
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
