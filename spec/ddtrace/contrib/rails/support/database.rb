# load the right adapter according to installed gem
module Datadog
  module Contrib
    module Rails
      module Test
        module Database
          module_function

          def load_adapter!
            begin
              connector = load_pg_adapter!
            rescue LoadError
              puts 'pg gem not found, trying another connector'
            end

            begin
              connector = load_mysql2_adapter!
            rescue LoadError
              puts 'mysql2 gem not found, trying another connector'
            end

            begin
              connector = load_jdbc_postgres_adapter!
            rescue LoadError
              puts 'jdbc-postgres gem not found, trying another connector'
            end

            begin
              connector = load_jdbc_mysql_adapter!
            rescue LoadError
              puts 'jdbc-mysql gem not found, trying another connector'
            end

            connector
          end

          def load_pg_adapter!
            require 'pg'

            # old versions of Rails (eg 3.0) require that sort of Monkey Patching,
            # since using ActiveRecord is tricky (version mismatch etc.)
            if ::Rails.version < '3.2.22.5'
              ::Rails::Application::Configuration.class_eval do
                def database_configuration
                  { 'test' => { 'adapter' => 'postgresql',
                                'encoding' => 'utf8',
                                'reconnect' => false,
                                'database' => 'postgres',
                                'pool' => 5,
                                'username' => 'postgres',
                                'password' => 'postgres',
                                'host' => 'localhost',
                                'port' => '55432' } }
                end
              end
            end

            'postgres://postgres:postgres@127.0.0.1:55432/postgres'
          end

          def load_jdbc_mysql_adapter!
            require 'activerecord-jdbcmysql-adapter'
            'mysql2://root:root@127.0.0.1:53306/mysql'
          end

          def load_jdbc_postgres_adapter!
            require 'activerecord-jdbcpostgresql-adapter'
            'postgres://postgres:postgres@127.0.0.1:55432/postgres'
          end

          def load_mysql2_adapter!
            require 'mysql2'
            'mysql2://root:root@127.0.0.1:53306/mysql'
          end
        end
      end
    end
  end
end
