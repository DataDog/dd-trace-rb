require 'active_record'
require 'rails/all'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'mysql2'
end


ActiveSupport.on_load(:active_record) do
  
end

ActiveSupport.on_load(:active_record) do

  
end

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# connecting to any kind of database is enough to test the integration
root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
port = ENV.fetch('TEST_MYSQL_PORT', '3306')
db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")

class ApplicationRecord < ActiveRecord::Base
  include ActiveStorage::Attached::Model
  self.abstract_class = true
end

class Article < ApplicationRecord
  include ActiveStorage::Attached::Model
  include ActiveStorage::Reflection::ActiveRecordExtensions
  ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)  
  has_one_attached :image
end

# check if the migration has been executed
# MySQL JDBC drivers require that, otherwise we get a
# "Table '?' already exists" error
begin
  Article.count()
  
rescue ActiveRecord::StatementInvalid
  logger.info 'Executing database migrations'
  ActiveRecord::Schema.define(version: 20161003090450) do
    create_table 'articles', force: :cascade do |t|
      t.string   'title'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
    end

    create_table :active_storage_blobs do |t|
      t.string   :key,        null: false
      t.string   :filename,   null: false
      t.string   :content_type
      t.text     :metadata
      t.bigint   :byte_size,  null: false
      t.string   :checksum,   null: false
      t.datetime :created_at, null: false

      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false
      t.references :blob,     null: false

      t.datetime :created_at, null: false

      t.index [ :record_type, :record_id, :name, :blob_id ], name: "index_active_storage_attachments_uniqueness", unique: true
    end
  end
else
  logger.info 'Database already exists; nothing to do'
end

# force an access to prevent extra spans during tests
Article.count()
