require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sequel/utils'

module Datadog
  module Contrib
    module Sequel
      # Adds instrumentation to Sequel::Dataset
      module Dataset
        def self.included(base)
          base.send(:include, Utils)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for instrumenting Sequel::Dataset
        module InstanceMethods
          def execute(sql, options = ::Sequel::OPTS, &block)
            trace_execute(proc { super(sql, options, &block) }, sql, options, &block)
          end

          def execute_ddl(sql, options = ::Sequel::OPTS, &block)
            trace_execute(proc { super(sql, options, &block) }, sql, options, &block)
          end

          def execute_dui(sql, options = ::Sequel::OPTS, &block)
            trace_execute(proc { super(sql, options, &block) }, sql, options, &block)
          end

          def execute_insert(sql, options = ::Sequel::OPTS, &block)
            trace_execute(proc { super(sql, options, &block) }, sql, options, &block)
          end

          private

          def trace_execute(super_method, sql, options, &block)
            tracer_options = datadog_tracer_options
            opts = parse_opts(sql, options)
            response = nil

            tracer_options[:tracer].trace('sequel.query') do |span|
              span.service = tracer_options[:service]
              span.resource = opts[:query]
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag('sequel.db.vendor', adapter_name)
              response = super_method.call(sql, options, &block)
            end
            response
          end

          def datadog_tracer_options
            pin = Datadog::Pin.get_from(db)
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
