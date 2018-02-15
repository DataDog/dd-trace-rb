# load the right adapter according to installed gem
module Datadog
  module Contrib
    module Rails
      module Test
        module Database
          module_function

          def configure!
            begin
              require 'pg'
              connector = 'postgres://postgres:postgres@127.0.0.1:55432/postgres'

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
            rescue LoadError
              puts 'pg gem not found, trying another connector'
            end

            begin
              require 'mysql2'
              connector = 'mysql2://root:root@127.0.0.1:53306/mysql'
            rescue LoadError
              puts 'mysql2 gem not found, trying another connector'
            end

            begin
              require 'activerecord-jdbcpostgresql-adapter'
              connector = 'postgres://postgres:postgres@127.0.0.1:55432/postgres'
            rescue LoadError
              puts 'jdbc-postgres gem not found, trying another connector'
            end

            begin
              require 'activerecord-jdbcmysql-adapter'
              connector = 'mysql2://root:root@127.0.0.1:53306/mysql'
            rescue LoadError
              puts 'jdbc-mysql gem not found, trying another connector'
            end

            connector
          end
        end
      end
    end
  end
end
