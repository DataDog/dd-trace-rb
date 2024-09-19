require 'datadog/demo_env'

Datadog::DemoEnv.print_env('Puma master environment')

workers Integer(ENV["WEB_CONCURRENCY"] || 1)
threads 2, Integer(ENV['WEB_MAX_THREADS'] || 24)

preload_app!

bind 'tcp://0.0.0.0:80'

on_worker_boot do
  Datadog::DemoEnv.print_env('Puma worker environment')
end
