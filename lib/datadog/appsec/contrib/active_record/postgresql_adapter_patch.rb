# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module ActiveRecord
        # AppSec module that will be prepended to ActiveRecord adapter
        module PostgreSQLAdapterPatch
          def internal_exec_query(sql, *args, **rest)
            scope = AppSec.active_scope
            return super unless scope

            ephemeral_data = {
              'server.db.statement' => sql,
              'server.db.system' => 'postgresql'
            }

            result = scope.processor_context.run({}, ephemeral_data, Datadog.configuration.appsec.waf_timeout)

            if result.status == :match
              Datadog::AppSec::Event.tag_and_keep!(scope, result)

              event = {
                waf_result: result,
                trace: scope.trace,
                span: scope.service_entry_span,
                actions: result.actions,
                sql: sql
              }
              scope.processor_context.events << event
            end

            super
          end
        end
      end
    end
  end
end
