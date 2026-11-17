# frozen_string_literal: true

require_relative "instrumentation"

module Datadog
  module AppSec
    module Contrib
      module ActiveRecord
        # AppSec patcher module for ActiveRecord
        module Patcher
          module AdapterInheritancePatch
            def inherited(subclass)
              super

              case subclass.name
              when "ActiveRecord::ConnectionAdapters::SQLite3Adapter" then Patcher.patch_sqlite3_adapter
              when "ActiveRecord::ConnectionAdapters::Mysql2Adapter" then Patcher.patch_mysql2_adapter
              when "ActiveRecord::ConnectionAdapters::PostgreSQLAdapter" then Patcher.patch_postgresql_adapter
              end
            end
          end

          def self.patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            ActiveSupport.on_load :active_record do
              ::ActiveRecord::ConnectionAdapters::AbstractAdapter.singleton_class.prepend(
                ::Datadog::AppSec::Contrib::ActiveRecord::Patcher::AdapterInheritancePatch,
              )

              if defined?(::ActiveRecord::ConnectionAdapters::SQLite3Adapter)
                ::Datadog::AppSec::Contrib::ActiveRecord::Patcher.patch_sqlite3_adapter
              end

              if defined?(::ActiveRecord::ConnectionAdapters::Mysql2Adapter)
                ::Datadog::AppSec::Contrib::ActiveRecord::Patcher.patch_mysql2_adapter
              end

              if defined?(::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
                ::Datadog::AppSec::Contrib::ActiveRecord::Patcher.patch_postgresql_adapter
              end
            end
          end

          def self.patch_sqlite3_adapter
            instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new("8.0")
              Instrumentation::PreprocessQueryAdapterPatch
            elsif ::ActiveRecord.gem_version >= Gem::Version.new("7.1")
              Instrumentation::InternalExecQueryAdapterPatch
            elsif ::ActiveRecord.gem_version.segments.first == 4
              Instrumentation::Rails4ExecQueryAdapterPatch
            else
              Instrumentation::ExecQueryAdapterPatch
            end

            ::ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(instrumentation_module)
            Patcher.instance_variable_set(:@patched, true)
          end

          def self.patch_mysql2_adapter
            instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new("8.0")
              Instrumentation::PreprocessQueryAdapterPatch
            elsif ::ActiveRecord.gem_version >= Gem::Version.new("7.1")
              Instrumentation::InternalExecQueryAdapterPatch
            elsif ::ActiveRecord.gem_version.segments.first == 4
              Instrumentation::Rails4ExecQueryAdapterPatch
            else
              Instrumentation::ExecQueryAdapterPatch
            end

            ::ActiveRecord::ConnectionAdapters::Mysql2Adapter.prepend(instrumentation_module)
            Patcher.instance_variable_set(:@patched, true)
          end

          def self.patch_postgresql_adapter
            instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new("8.0")
              Instrumentation::PreprocessQueryAdapterPatch
            elsif ::ActiveRecord.gem_version.segments.first == 4
              Instrumentation::Rails4ExecuteAndClearAdapterPatch
            else
              Instrumentation::ExecuteAndClearAdapterPatch
            end

            if defined?(::ActiveRecord::ConnectionAdapters::JdbcAdapter)
              instrumentation_module = if ::ActiveRecord.gem_version >= Gem::Version.new("8.0")
                Instrumentation::PreprocessQueryAdapterPatch
              elsif ::ActiveRecord.gem_version >= Gem::Version.new("7.1")
                Instrumentation::InternalExecQueryAdapterPatch
              elsif ::ActiveRecord.gem_version.segments.first == 4
                Instrumentation::Rails4ExecQueryAdapterPatch
              else
                Instrumentation::ExecQueryAdapterPatch
              end
            end

            ::ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(instrumentation_module)
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
