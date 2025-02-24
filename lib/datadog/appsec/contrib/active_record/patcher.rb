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
            patch_proc = lambda do |adapter_class, is_postgres: false|
              instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new('7.1')
                                         Instrumentation::InternalExecQueryAdapterPatch
                                       else
                                         Instrumentation::ExecQueryAdapterPatch
                                       end

              if is_postgres && !defined?(::ActiveRecord::ConnectionAdapters::JdbcAdapter)
                instrumentation_module = Instrumentation::ExecuteAndClearAdapterPatch
              end

              adapter_class.prepend(instrumentation_module)
            end

            ActiveSupport.on_load :active_record do
              if defined?(::ActiveRecord::ConnectionAdapters::SQLite3Adapter)
                patch_proc.call(::ActiveRecord::ConnectionAdapters::SQLite3Adapter)
              else
                ActiveSupport.on_load :active_record_sqlite3adapter do
                  patch_proc.call(::ActiveRecord::ConnectionAdapters::SQLite3Adapter)
                end
              end

              if defined?(::ActiveRecord::ConnectionAdapters::Mysql2Adapter)
                patch_proc.call(::ActiveRecord::ConnectionAdapters::Mysql2Adapter)
              else
                ActiveSupport.on_load :active_record_mysql2adapter do
                  patch_proc.call(::ActiveRecord::ConnectionAdapters::Mysql2Adapter)
                end
              end

              if defined?(::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
                patch_proc.call(::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter, is_postgres: true)
              else
                ActiveSupport.on_load :active_record_postgresqladapter do
                  patch_proc.call(::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter, is_postgres: true)
                end
              end
            end
          end
        end
      end
    end
  end
end
