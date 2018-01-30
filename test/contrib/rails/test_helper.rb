require 'logger'
require 'bundler/setup'
require 'minitest/autorun'

require 'rails'

# load the right adapter according to installed gem
begin
  require 'pg'
  connector = 'postgres://postgres:postgres@127.0.0.1:55432/postgres'

  # old versions of Rails (eg 3.0) require that sort of Monkey Patching,
  # since using ActiveRecord is tricky (version mismatch etc.)
  if Rails.version < '3.2.22.5'
    module Rails
      class Application
        class Configuration
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

# logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Rails settings
ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = connector

# switch Rails import according to installed
# version; this is controlled with Appraisals
logger.info "Testing against Rails #{Rails.version} with connector '#{connector}'"

case Rails.version
when '5.1.4'
  require 'contrib/rails/apps/rails5'
when '5.0.1'
  require 'contrib/rails/apps/rails5'
when '4.2.7.1'
  require 'contrib/rails/apps/rails4'
when '3.2.22.5'
  require 'test/unit'
  require 'contrib/rails/apps/rails3'
  require 'contrib/rails/core_extensions'
when '3.0.20'
  require 'test/unit'
  require 'contrib/rails/apps/rails3'
  require 'contrib/rails/core_extensions'
else
  logger.error 'A Rails app for this version is not found!'
end

def app_name
  Datadog::Contrib::Rails::Utils.app_name
end
