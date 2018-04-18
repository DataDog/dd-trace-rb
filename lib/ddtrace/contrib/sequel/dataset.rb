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

          # If prepending is supported
          if base.respond_to?(:prepend)
            base.send(:prepend, InstanceMethods)
          else
            patch(base)
          end
        end

        # rubocop:disable Metrics/MethodLength
        def self.patch(base)
          Datadog::Patcher.without_warnings do
            base.send(:define_method, :datadog_trace_execute) do |super_method, sql, options, &block|
              pin = Datadog::Pin.get_from(self)
              return super_method.call(sql, options, &block) unless pin && pin.tracer

              opts = parse_opts(sql, options)
              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = super_method.call(sql, options, &block)
              end
              response
            end

            # Dataset#initialize
            base.send(:alias_method, :initialize_without_datadog, :initialize)
            base.send(:remove_method, :initialize)
            base.send(:define_method, :initialize) do |*args|
              pin = Datadog::Pin.new(Patcher::SERVICE, app: Patcher::APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            # Dataset#execute
            base.send(:alias_method, :execute_without_datadog, :execute)
            base.send(:remove_method, :execute)
            base.send(:define_method, :execute) do |sql, options = ::Sequel::OPTS, &block|
              datadog_trace_execute(proc { execute_without_datadog(sql, options, &block) }, sql, options, &block)
            end

            # Dataset#execute_ddl
            base.send(:alias_method, :execute_ddl_without_datadog, :execute_ddl)
            base.send(:remove_method, :execute_ddl)
            base.send(:define_method, :execute_ddl) do |sql, options = ::Sequel::OPTS, &block|
              datadog_trace_execute(proc { execute_ddl_without_datadog(sql, options, &block) }, sql, options, &block)
            end

            # Dataset#execute_dui
            base.send(:alias_method, :execute_dui_without_datadog, :execute_dui)
            base.send(:remove_method, :execute_dui)
            base.send(:define_method, :execute_dui) do |sql, options = ::Sequel::OPTS, &block|
              datadog_trace_execute(proc { execute_dui_without_datadog(sql, options, &block) }, sql, options, &block)
            end

            # Dataset#execute_dui
            base.send(:alias_method, :execute_insert_without_datadog, :execute_insert)
            base.send(:remove_method, :execute_insert)
            base.send(:define_method, :execute_insert) do |sql, options = ::Sequel::OPTS, &block|
              datadog_trace_execute(proc { execute_insert_without_datadog(sql, options, &block) }, sql, options, &block)
            end
          end
        end

        # Instance methods for instrumenting Sequel::Dataset
        module InstanceMethods
          def initialize(*args)
            pin = Datadog::Pin.new(Patcher::SERVICE, app: Patcher::APP, app_type: Datadog::Ext::AppTypes::DB)
            pin.onto(self)
            super(*args)
          end

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
            pin = Datadog::Pin.get_from(self)
            return super_method.call(sql, options, &block) unless pin && pin.tracer

            opts = parse_opts(sql, options)
            response = nil

            pin.tracer.trace('sequel.query') do |span|
              span.service = pin.service
              span.resource = opts[:query]
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag('sequel.db.vendor', adapter_name)
              response = super_method.call(sql, options, &block)
            end
            response
          end
        end
      end
    end
  end
end
