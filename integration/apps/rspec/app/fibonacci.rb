require_relative 'datadog'

def fib(n)
  n <= 1 ? n : fib(n-1) + fib(n-2)
end

def trace(*options, &block)
  raise ArgumentError('Must provide trace block') unless block_given?

  if Datadog::DemoEnv.feature?('tracing')
    Datadog::Tracing.trace(*options, &block)
  else
    yield
  end
end

def generate_fib
  loop do
    n = rand(25..35)

    trace('compute.fibonacci') do |span|
      result = fib(n)
      span.set_metric('operation.fibonacci.n', n)
      span.set_metric('operation.fibonacci.result', result)
      yield(span) if block_given?
    end

    sleep(0.1)
  end
end
