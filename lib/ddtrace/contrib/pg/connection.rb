require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/pg/ext'

module Datadog
  module Contrib
    module Pg
      # PG::Connection patch module
      module Connection
        module_function

        def included(base)
          base.send(:prepend, InstanceMethods)
        end

        # PG::Connection patch instance methods
        module InstanceMethods

          # sync_exec(sql) -> PG::Result
          # sync_exec(sql) {|pg_result| block}
          def sync_exec(sql)
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag(Ext::TAG_DB_NAME, db)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              super # this will pass all args, including the block
            end
          end

          # sync_exec_params(sql, params[, result_format[, type_map]] ) -> PG::Result
          # sync_exec_params(sql, params[, result_format[, type_map]] ) {|pg_result| block }
          # exec_params (and async version) is parsed with rb_scan_args like so:
          # rb_scan_args(argc, argv, "22", &command, &paramsData.params, &in_res_fmt, &paramsData.typemap);
          # meaning it expects 2 required arguments and 2 explicit optional
          def sync_exec_params(sql, params, result_format = nil, type_map = nil)
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag(Ext::TAG_DB_NAME, db)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              super # this will pass all args, including the block
            end
          end

          # async_exec(sql) -> PG::Result OR
          # async_exec(sql) {|pg_result| block}
          def async_exec(sql)
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag(Ext::TAG_DB_NAME, db)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              super # this will pass all args, including the block
            end
          end

          # async_exec_params(sql, params[, result_format[, type_map]] ) -> PG::Result
          # async_exec_params(sql, params[, result_format[, type_map]] ) {|pg_result| block }
          def async_exec_params(sql, params, result_format = nil, type_map = nil)
            datadog_pin.tracer.trace(Ext::SPAN_QUERY) do |span|
              span.resource = sql
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag(Ext::TAG_DB_NAME, db)
              span.set_tag(Datadog::Ext::NET::TARGET_HOST, host)
              span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
              super # this will pass all args, including the block
            end
          end

          def datadog_pin
            @datadog_pin ||= Datadog::Pin.new(
              Datadog.configuration[:pg][:service_name],
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::DB,
              tracer: Datadog.configuration[:pg][:tracer]
            )
          end
        end
      end
    end
  end
end
