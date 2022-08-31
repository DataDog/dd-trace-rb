require 'datadog/demo_env'

Datadog::DemoEnv.print_env('Puma master environment')

workers Integer(ENV["WEB_CONCURRENCY"] || 1)
threads 2, Integer(ENV['RAILS_MAX_THREADS'] || 24)

preload_app!

bind 'tcp://0.0.0.0:80'
environment ENV['RAILS_ENV'] || 'development'

on_worker_boot do
  ActiveSupport.on_load(:active_record) do
    ActiveRecord::Base.establish_connection
  end

  Datadog::DemoEnv.print_env('Puma worker environment')
end

before_fork do
  ActiveRecord::Base.connection_pool.disconnect!
  #$redis.pool_shutdown { |conn| conn.quit }
end
