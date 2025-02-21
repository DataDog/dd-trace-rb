# frozen_string_literal: true

require_relative 'instrumentation'

module Datadog
  module AppSec
    module Contrib
      module ActiveRecord
        # AppSec patcher module for ActiveRecord
        module Patcher
          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            if ::ActiveRecord.gem_version >= Gem::Version.new('7.1')
              instrumentation_module = Instrumentation::InternalExecQueryAdapterPatch

              # Load Hooks for all adapters are present starting with ActiveRecord 7.1
              ActiveSupport.on_load :active_record_sqlite3adapter do
                ::ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(instrumentation_module)
              end

              ActiveSupport.on_load :active_record_mysql2adapter do
                ::ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(instrumentation_module)
              end

              ActiveSupport.on_load :active_record_postgresqladapter do
                ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(instrumentation_module)
              end
            else
              instrumentation_module = Instrumentation::ExecQueryAdapterPatch

              ActiveSupport.on_load :active_record do
                if defined?(::ActiveRecord::ConnectionAdapters::SQLite3Adapter)
                  ::ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(instrumentation_module)
                end

                if defined?(::ActiveRecord::ConnectionAdapters::Mysql2Adapter)
                  ::ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(instrumentation_module)
                end

                if defined?(::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
                  unless defined?(::ActiveRecord::ConnectionAdapters::JdbcAdapter)
                    instrumentation_module = Instrumentation::ExecuteAndClearAdapterPatch
                  end

                  ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(instrumentation_module)
                end
              end
            end
          end
        end
      end
    end
  end
end
