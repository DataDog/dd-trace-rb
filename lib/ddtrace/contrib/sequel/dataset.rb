require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sequel/utils'

module Datadog
  module Contrib
    module Sequel
      # Adds instrumentation to Sequel::Dataset
      module Dataset
        def self.included(base)
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

          def datadog_pin
            Datadog::Pin.get_from(db)
          end

          private

          def trace_execute(super_method, sql, options, &block)
            opts = Utils.parse_opts(sql, options, db.opts)
            response = nil

            datadog_pin.tracer.trace('sequel.query') do |span|
              span.service = datadog_pin.service
              span.resource = opts[:query]
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag('sequel.db.vendor', adapter_name)
              response = super_method.call(sql, options, &block)
            end
            response
          end

          def adapter_name
            Utils.adapter_name(db)
          end
        end
      end
    end
  end
end
