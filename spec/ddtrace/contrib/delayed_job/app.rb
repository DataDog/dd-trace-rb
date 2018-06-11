require 'active_record'
require 'mysql2'
require 'delayed_job'
require 'delayed_job_active_record'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# connecting to any kind of database is enough to test the integration
root_pw = ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')
host = ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')
port = ENV.fetch('TEST_MYSQL_PORT', '3306')
db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
ActiveRecord::Base.establish_connection("mysql2://root:#{root_pw}@#{host}:#{port}/#{db}")

# check if the migration has been executed
# MySQL JDBC drivers require that, otherwise we get a
# "Table '?' already exists" error
begin
  Delayed::Job.count()
rescue ActiveRecord::StatementInvalid
  logger.info 'Executing database migrations'
  ActiveRecord::Schema.define(version: 2018_05_25_114131) do
    create_table "delayed_jobs", force: :cascade do |t|
      t.integer "priority", default: 0, null: false
      t.integer "attempts", default: 0, null: false
      t.text "handler", null: false
      t.text "last_error"
      t.datetime "run_at"
      t.datetime "locked_at"
      t.datetime "failed_at"
      t.string "locked_by"
      t.string "queue"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.index ["priority", "run_at"], name: "delayed_jobs_priority"
    end
  end
else
  logger.info 'Database already exists; nothing to do'
end
