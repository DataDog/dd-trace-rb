# frozen_string_literal: true

require_relative '../patcher'
require_relative 'instrumentation'

module Datadog
  module AppSec
    module Contrib
      module ActiveRecord
        # AppSec patcher module for ActiveRecord
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            ActiveSupport.on_load :active_record do
              instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new('7.1')
                                         Instrumentation::InternalExecQueryAdapterPatch
                                       else
                                         Instrumentation::ExecQueryAdapterPatch
                                       end

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
