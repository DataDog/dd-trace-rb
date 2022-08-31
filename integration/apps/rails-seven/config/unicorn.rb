require 'datadog/demo_env'

# config/unicorn.rb
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 1)
timeout 15
listen 80
preload_app true

Datadog::DemoEnv.print_env('Unicorn master environment')

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end

  defined?(ActiveRecord::Base) and
    ActiveRecord::Base.establish_connection

  Datadog::DemoEnv.print_env('Unicorn worker environment')
end
