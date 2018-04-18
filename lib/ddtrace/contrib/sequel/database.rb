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
