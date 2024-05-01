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
        profiler_threads: Thread.list.map(&:name).select { |it| it && it.include?('Profiling') },
      )
    ]
  end
end
