RSpec.configure do |c|
  c.around(:example, :delayed_job_active_record) do |example|
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    ActiveRecord::Schema.define(version: 2018_05_25_114131) do
      create_table 'delayed_jobs', force: :cascade do |t|
        t.integer 'priority', default: 0, null: false
        t.integer 'attempts', default: 0, null: false
        t.text 'handler', null: false
        t.text 'last_error'
        t.datetime 'run_at'
        t.datetime 'locked_at'
        t.datetime 'failed_at'
        t.string 'locked_by'
        t.string 'queue'
        t.datetime 'created_at'
        t.datetime 'updated_at'
      end
    end

    example.run

    ActiveRecord::Base.connection.close
  end
end
