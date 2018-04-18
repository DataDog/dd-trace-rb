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

          # If prepending is supported
          if base.respond_to?(:prepend)
            base.send(:prepend, InstanceMethods)
          else
            patch(base)
          end
        end

        def self.patch(base)
          Datadog::Patcher.without_warnings do
            # Database#initialize
            base.send(:alias_method, :initialize_without_datadog, :initialize)
            base.send(:remove_method, :initialize)
            base.send(:define_method, :initialize) do |*args|
              pin = Datadog::Pin.new(Patcher::SERVICE, app: Patcher::APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            # Database#run
            base.send(:alias_method, :run_without_datadog, :run)
            base.send(:remove_method, :run)
            base.send(:define_method, :run) do |sql, options = ::Sequel::OPTS|
              pin = Datadog::Pin.get_from(self)
              return run_without_datadog(sql, options) unless pin && pin.tracer

              opts = parse_opts(sql, options)

              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = run_without_datadog(sql, options)
              end
              response
            end
          end
        end

        # Instance methods for instrumenting Sequel::Database
        module InstanceMethods
          def initialize(*args)
            pin = Datadog::Pin.new(Patcher::SERVICE, app: Patcher::APP, app_type: Datadog::Ext::AppTypes::DB)
            pin.onto(self)
            super(*args)
          end

          def run(sql, options = ::Sequel::OPTS)
            pin = Datadog::Pin.get_from(self)
            return super(sql, options) unless pin && pin.tracer

            opts = parse_opts(sql, options)

            response = nil

            pin.tracer.trace('sequel.query') do |span|
              span.service = pin.service
              span.resource = opts[:query]
              span.span_type = Datadog::Ext::SQL::TYPE
              span.set_tag('sequel.db.vendor', adapter_name)
              response = super(sql, options)
            end
            response
          end
        end
      end
    end
  end
end
