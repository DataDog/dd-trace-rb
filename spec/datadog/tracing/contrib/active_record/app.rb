# typed: ignore

require 'active_record'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'mysql2'
end

logger = Logger.new($stdout)
logger.level = Logger::INFO

# connecting to any kind of database is enough to test the integration
# root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
# host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
# port = ENV.fetch('TEST_MYSQL_PORT', '3306')
# db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
# ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class User < ApplicationRecord
  has_many :articles
end

class Article < ApplicationRecord
  belongs_to :user
end

# check if the migration has been executed
# MySQL JDBC drivers require that, otherwise we get a
# "Table '?' already exists" error
begin
  Article.count
rescue ActiveRecord::StatementInvalid
  logger.info 'Executing database migrations'
  ActiveRecord::Schema.define(version: 20161003090450) do
    create_table "users", force: true do |t|
      t.string   "name"

      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table 'articles', force: :cascade do |t|
      t.string   'title'
      t.references :user, index: true, foreign_key: true, on_delete: :cascade

      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
    end
  end

  # Seed database
  2.times do |i|
    user = User.create!(name: "user_#{i}")

    3.times do|j|
      Article.create!(title: "article_#{i}_#{j}", user: user)
    end
  end
else
  logger.info 'Database already exists; nothing to do'
end

# force an access to prevent extra spans during tests
Article.count
User.count
