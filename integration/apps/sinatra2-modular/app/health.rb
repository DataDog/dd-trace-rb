require 'sinatra/base'
require 'datadog'

class Health < Sinatra::Base
  # register Datadog::Tracing::Contrib::Sinatra::Tracer

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
end
