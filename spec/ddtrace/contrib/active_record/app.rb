require 'active_record'
require 'mysql2'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

require_relative '../rails/support/database'

adapter = Datadog::Contrib::Rails::Test::Database.load_adapter!
ActiveRecord::Base.establish_connection(adapter)

def adapter_name
  Datadog::Utils::Database.normalize_vendor(ActiveRecord::Base.connection_config[:adapter])
end

def database_name
  ActiveRecord::Base.connection_config[:database]
end

# def self.adapter_host
#   connection_config[:host]
# end
#
# def self.adapter_port
#   connection_config[:port]
# end

# ENV['RAILS_ENV'] = 'test'
# ENV['DATABASE_URL'] = adapter

# connecting to any kind of database is enough to test the integration
# root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
# host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
# port = ENV.fetch('TEST_MYSQL_PORT', '3306')
# db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
# ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Article < ApplicationRecord
end

# check if the migration has been executed
# MySQL JDBC drivers require that, otherwise we get a
# "Table '?' already exists" error
begin
  Article.first
rescue ActiveRecord::StatementInvalid
  logger.info 'Executing database migrations'
  ActiveRecord::Schema.define(version: 20161003090450) do
    create_table 'articles', force: :cascade do |t|
      t.string   'title'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
    end
  end
  Article.first
else
  logger.info 'Database already exists; nothing to do'
end

# force an access to prevent extra spans during tests
Article.first
