require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sequel/utils'

module Datadog
  module Contrib
    module Sequel
      # Adds instrumentation to Sequel::Database
      module Database
        def self.included(base)
          base.send(:include, Utils)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for instrumenting Sequel::Database
        module InstanceMethods
          def initialize(*args)
            pin = Datadog::Pin.new(
              Datadog.configuration[:sequel][:service_name],
              app: Patcher::APP,
              app_type: Datadog::Ext::AppTypes::DB
            )
            pin.onto(self)
            super(*args)
          end

          def run(sql, options = ::Sequel::OPTS)
            tracer_options = datadog_tracer_options
            opts = parse_opts(sql, options)

            response = nil

            tracer_options[:tracer].trace('sequel.query') do |span|
              span.service = tracer_options[:service]
              span.resource = opts[:query]
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag('sequel.db.vendor', adapter_name)
              response = super(sql, options)
            end
            response
          end

          private

          def datadog_tracer_options
            pin = Datadog::Pin.get_from(self)
            {
              tracer: (pin.nil? ? nil : pin.tracer) || Datadog.configuration[:sequel][:tracer],
              service: (pin.nil? ? nil : pin.service) || Datadog.configuration[:sequel][:service_name]
            }
          end
        end
      end
    end
  end
end
