require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/patching/base'

module Datadog
  module Contrib
    module Mysql2
      # Mysql2::Client patch
      module Client
        extend Patching::Base

        datadog_patch_method(:query) do |sql, options|
          datadog_pin.tracer.trace('mysql2.query') do |span|
            span.resource = sql
            span.service = datadog_pin.service
            span.span_type = Datadog::Ext::SQL::TYPE
            span.set_tag('mysql2.db.name', query_options[:database])
            span.set_tag('out.host', query_options[:host])
            span.set_tag('out.port', query_options[:port])
            super(sql, options)
          end
        end
      end
    end
  end
end
