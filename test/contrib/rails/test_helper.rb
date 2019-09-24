require 'logger'
require 'bundler/setup'
require 'minitest/autorun'

require 'rails'

# load the right adapter according to installed gem
begin
  require 'pg'
  user = ENV.fetch('TEST_POSTGRES_USER', 'postgres')
  pw = ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres')
  host = ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1')
  port = ENV.fetch('TEST_POSTGRES_PORT', 5432)
  db = ENV.fetch('TEST_POSTGRES_DB', 'postgres')
  connector = "postgres://#{user}:#{pw}@#{host}:#{port}/#{db}"

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
rescue LoadError
  puts 'pg gem not found, trying another connector'
end

begin
  require 'mysql2'
  root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
  host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
  port = ENV.fetch('TEST_MYSQL_PORT', '3306')
  db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
  connector = "mysql2://root:#{root_pw}@#{host}:#{port}/#{db}"
rescue LoadError
  puts 'mysql2 gem not found, trying another connector'
end

begin
  require 'activerecord-jdbcpostgresql-adapter'
  user = ENV.fetch('TEST_POSTGRES_USER', 'postgres')
  pw = ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres')
  host = ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1')
  port = ENV.fetch('TEST_POSTGRES_PORT', 5432)
  db = ENV.fetch('TEST_POSTGRES_DB', 'postgres')
  connector = "postgres://#{user}:#{pw}@#{host}:#{port}/#{db}"
rescue LoadError
  puts 'jdbc-postgres gem not found, trying another connector'
end

begin
  require 'activerecord-jdbcmysql-adapter'
  root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
  host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
  port = ENV.fetch('TEST_MYSQL_PORT', '3306')
  db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
  connector = "mysql2://root:#{root_pw}@#{host}:#{port}/#{db}"
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
when /^6\.0/
  require 'contrib/rails/apps/rails6'
when /^5\.2/
  require 'contrib/rails/apps/rails5'
when /^4\.2/
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
  logger.error "A Rails app for #{Rails.version} is not found!"
end

def app_name
  Datadog::Contrib::Rails::Utils.app_name
end
