require 'sinatra/base'
require 'datadog'
require_relative 'parent'

# Inherit from another app to verify middleware/extension inheritance
class Basic < Parent
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

  private

  def fib(n)
    n <= 1 ? n : fib(n - 1) + fib(n - 2)
  end
end
