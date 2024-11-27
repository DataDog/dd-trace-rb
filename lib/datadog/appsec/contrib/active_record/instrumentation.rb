# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module ActiveRecord
        # AppSec module that will be prepended to ActiveRecord adapter
        module Instrumentation
          module_function

          def detect_sql_injection(sql, adapter_name)
            scope = AppSec.active_scope
            return unless scope

            ephemeral_data = {
              'server.db.statement' => sql,
              'server.db.system' => adapter_name.downcase.gsub(/\d{1}\z/, '')
            }

            waf_timeout = Datadog.configuration.appsec.waf_timeout
            result = scope.processor_context.run({}, ephemeral_data, waf_timeout)

            if result.status == :match
              Datadog::AppSec::Event.tag_and_keep!(scope, result)

              event = {
                waf_result: result,
                trace: scope.trace,
                span: scope.service_entry_span,
                sql: sql,
                actions: result.actions
              }
              scope.processor_context.events << event
            end
          end

          # patch for all adapters in ActiveRecord >= 7.1
          module InternalExecQueryAdapterPatch
            def internal_exec_query(sql, *args, **rest)
              Instrumentation.detect_sql_injection(sql, adapter_name)

              super
            end
          end

          # patch for postgres adapter in ActiveRecord < 7.1
          module ExecuteAndClearAdapterPatch
            def execute_and_clear(sql, *args, **rest)
              Instrumentation.detect_sql_injection(sql, adapter_name)

              super
            end
          end

          # patch for mysql2 and sqlite3 adapters in ActiveRecord < 7.1
          # this patch is also used when using JDBC adapter
          module ExecQueryAdapterPatch
            def exec_query(sql, *args, **rest)
              Instrumentation.detect_sql_injection(sql, adapter_name)

              super
            end
          end
        end
      end
    end
  end
end
