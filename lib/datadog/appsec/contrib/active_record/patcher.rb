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
              if defined? ::ActiveRecord::ConnectionAdapters::SQLite3Adapter
                ::ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(Patcher.prepended_class_name(:sqlite3))
              end

              if defined? ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
                ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(Patcher.prepended_class_name(:postgresql))
              end

              if defined? ::ActiveRecord::ConnectionAdapters::Mysql2Adapter
                ::ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(Patcher.prepended_class_name(:mysql2))
              end
            end
          end

          def prepended_class_name(adapter_name)
            if ::ActiveRecord.gem_version >= Gem::Version.new('7.1')
              Instrumentation::InternalExecQueryAdapterPatch
            elsif adapter_name == :postgresql && !defined?(::ActiveRecord::ConnectionAdapters::JdbcAdapter)
              Instrumentation::ExecuteAndClearAdapterPatch
            else
              Instrumentation::ExecQueryAdapterPatch
            end
          end
        end
      end
    end
  end
end
