require 'ddtrace'

Datadog.configure do |c|
  c.tracer.enabled = true
end

def fib(n)
  return n if n <= 1
  Thread.pass
  fib(n-1) + fib(n-2)
end

loop do
  Datadog.tracer.trace('test-trace') do
    fib(25)
    sleep(1)
  end
end
