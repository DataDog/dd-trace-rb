require 'active_record'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'mysql2'
end

logger = Logger.new($stdout)
logger.level = Logger::INFO

# connecting to any kind of database is enough to test the integration
root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
port = ENV.fetch('TEST_MYSQL_PORT', '3306')
db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Article < ApplicationRecord
end

# check if the migration has been executed
# MySQL JDBC drivers require that, otherwise we get a
# "Table '?' already exists" error
begin
  Article.count
rescue ActiveRecord::StatementInvalid
  logger.info 'Executing database migrations'
  ActiveRecord::Schema.define(version: 20161003090450) do
    create_table 'articles', force: :cascade do |t|
      t.string   'title'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
    end
  end
else
  logger.info 'Database already exists; nothing to do'
end

# force an access to prevent extra spans during tests
Article.count
