# load the right adapter according to installed gem
module Datadog
  module Contrib
    module Rails
      module Test
        module Database
          module_function

          # rubocop:disable Metrics/MethodLength
          def load_adapter!
            [
              'pg',
              'mysql2',
              'activerecord-jdbcpostgresql-adapter',
              'activerecord-jdbcmysql-adapter'
            ].each do |adapter|
              begin
                require adapter

                if adapter == 'pg'
                  connector = postgres_url
                  # old versions of Rails (eg 3.0) require that sort of Monkey Patching,
                  # since using ActiveRecord is tricky (version mismatch etc.)
                  if ::Rails.version < '3.2.22.5'
                    ::Rails::Application::Configuration.class_eval do
                      def database_configuration
                        { 'test' => { 'adapter' => 'postgresql',
                                      'encoding' => 'utf8',
                                      'reconnect' => false,
                                      'database' => ENV.fetch('TEST_POSTGRES_DB', 'postgres'),
                                      'pool' => 5,
                                      'username' => ENV.fetch('TEST_POSTGRES_USER', 'postgres'),
                                      'password' => ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres'),
                                      'host' => ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1'),
                                      'port' => ENV.fetch('TEST_POSTGRES_PORT', 5432) } }
                      end
                    end
                  end
                elsif adapter.include?('postgres')
                  connector = postgres_url
                elsif adapter.include?('mysql')
                  connector = mysql_url
                end
              rescue LoadError
                puts "#{adapter} gem not found, trying another connector"
              else
                return connector
              end
            end

            raise 'No database adapter found!'
          end

          def postgres_url
            hash = postgres_hash
            "postgres://#{hash[:username]}:#{hash[:password]}@#{hash[:host]}:#{hash[:port]}/#{hash[:database]}"
          end

          def postgres_hash
            {
              database: ENV.fetch('TEST_POSTGRES_DB', 'postgres'),
              host: ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1'),
              password: ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres'),
              port: ENV.fetch('TEST_POSTGRES_PORT', 5432),
              username: ENV.fetch('TEST_POSTGRES_USER', 'postgres')
            }
          end

          def mysql_url
            hash = mysql_hash
            "mysql2://root:#{hash[:password]}@#{hash[:host]}:#{hash[:port]}/#{hash[:database]}"
          end

          def mysql_hash
            {
              database: ENV.fetch('TEST_MYSQL_DB', 'mysql'),
              host: ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'),
              password: ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root'),
              port: ENV.fetch('TEST_MYSQL_PORT', '3306')
            }
          end
        end
      end
    end
  end
end
