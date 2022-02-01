# typed: false
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/sequel/ext'
require 'datadog/tracing/contrib/sequel/utils'

module Datadog
  module Tracing
    module Contrib
      module Sequel
        # Adds instrumentation to Sequel::Database
        module Database
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for instrumenting Sequel::Database
          module InstanceMethods
            def run(sql, options = ::Sequel::OPTS)
              opts = parse_opts(sql, options)

              response = nil

              Tracing.trace(Ext::SPAN_QUERY) do |span|
                span.service =  Datadog.configuration_for(self, :service_name) \
                                || Tracing.configuration[:sequel][:service_name] \
                                || adapter_name
                span.resource = opts[:query]
                span.span_type = Tracing::Metadata::Ext::SQL::TYPE
                Utils.set_common_tags(span, self)
                span.set_tag(Ext::TAG_DB_VENDOR, adapter_name)
                response = super(sql, options)
              end
              response
            end

            private

            def adapter_name
              Utils.adapter_name(self)
            end

            def parse_opts(sql, opts)
              db_opts = if ::Sequel::VERSION < '3.41.0' && self.class.to_s !~ /Dataset$/
                          @opts
                        elsif instance_variable_defined?(:@pool) && @pool
                          @pool.db.opts
                        end
              sql = sql.is_a?(::Sequel::SQL::Expression) ? literal(sql) : sql.to_s

              Utils.parse_opts(sql, opts, db_opts)
            end
          end
        end
      end
    end
  end
end
