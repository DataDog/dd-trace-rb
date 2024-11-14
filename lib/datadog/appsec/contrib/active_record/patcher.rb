# frozen_string_literal: true

require_relative '../patcher'
require_relative 'sqlite3_adapter_patch'
require_relative 'postgresql_adapter_patch'
require_relative 'mysql2_adapter_patch'

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
                ::ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(SQLite3AdapterPatch)
              end

              if defined? ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
                ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(PostgreSQLAdapterPatch)
              end

              if defined? ::ActiveRecord::ConnectionAdapters::Mysql2Adapter
                ::ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(Mysql2AdapterPatch)
              end
            end
          end
        end
      end
    end
  end
end
