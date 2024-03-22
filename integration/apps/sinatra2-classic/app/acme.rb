require 'sinatra'
require 'datadog'

Datadog.configure do |c|
  c.service = 'acme-sinatra2-classic'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
    c.tracing.instrument :sinatra
  end

  if Datadog::DemoEnv.feature?('appsec')
    c.appsec.enabled = true
    c.appsec.instrument :sinatra
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

get '/' do
  'Hello world!'
end

get '/health' do
  204
end

get '/health/detailed' do
  [
    200,
    { 'content-type' => 'application/json' },
    JSON.generate(
      webserver_process: $PROGRAM_NAME,
      profiler_available: Datadog::Profiling.start_if_enabled,
      # NOTE: Threads can't be named on Ruby 2.1 and 2.2
      profiler_threads: (unless RUBY_VERSION < '2.3'
                           (Thread.list.map(&:name).select do |it|
                              it && it.include?('Profiling')
                            end)
                         end)
    )
  ]
end

get '/basic/default' do
  200
end

get '/basic/fibonacci' do
  n = rand(25..35)
  result = fib(n)

  [
    200,
    { 'content-type' => 'text/plain' },
    ["Basic: Fibonacci(#{n}): #{result}"]
  ]
end

def fib(n)
  n <= 1 ? n : fib(n - 1) + fib(n - 2)
end
