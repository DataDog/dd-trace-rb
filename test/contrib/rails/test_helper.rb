require 'logger'
require 'bundler/setup'
require 'minitest/autorun'

require 'rails'

# load the right adapter according to installed gem
begin
  require 'pg'
  connector = 'postgres://postgres:postgres@127.0.0.1:55432/postgres'
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
when '5.0.0.1'
  require 'contrib/rails/apps/rails5'
when '4.2.7.1'
  require 'contrib/rails/apps/rails4'
when '3.2.22.5'
  require 'test/unit'
  require 'contrib/rails/apps/rails3'
else
  logger.error 'A Rails app for this version is not found!'
end
