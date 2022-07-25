require 'sinatra/base'
require 'ddtrace'

class Basic < Sinatra::Base
  # register Datadog::Tracing::Contrib::Sinatra::Tracer

  get '/basic/default' do
    200
  end

  get '/basic/fibonacci' do
    n = rand(25..35)
    result = fib(n)

    [
      200,
      { 'Content-Type' => 'text/plain' },
      ["Basic: Fibonacci(#{n}): #{result}"]
    ]
  end

  private

  def fib(n)
    n <= 1 ? n : fib(n - 1) + fib(n - 2)
  end
end
