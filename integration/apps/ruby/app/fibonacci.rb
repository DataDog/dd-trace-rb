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

if defined?(Ractor)
  # Ractor version
  # DEV: Disabled for now because Ractors cannot access ENV.
  #      This results in a shareable-object violation.
  #      Enable when we figure out how to make DemoEnv ractor-safe.

  # require 'securerandom'
  # ractors = []

  # 3.times do |i|
  #   ractors << Ractor.new do
  #     ractor_id = SecureRandom.uuid
  #     generate_fib { |span| span.set_tag('ractor.id', ractor_id) }
  #   end
  # end

  # # Wait indefinitely for ractors
  # loop do
  #   ractors.collect(&:take)
  # end
  
  # DEV: Use single-threaded version instead for now...
  generate_fib
else
  # Single-threaded version
  generate_fib
end
