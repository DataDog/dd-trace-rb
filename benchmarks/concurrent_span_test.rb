ENV['RAILS_ENV'] = 'production'
require 'English'

# Benchmark Configuration container
module TestConfiguration
  module_function

  def iteration_count
    10000
  end
end

require 'bundler/setup'
require 'ddtrace'
require 'concurrent/atomic/atomic_fixnum'

# approximate operations
class TestWithoutDatadog
  def perform(iterations = 100)
    iterations.times do
      (proc { sleep(0.001) }).call
    end
  end
end

# real test
class Test
  def perform(iterations = 100)

    iterations.times do
      Datadog.tracer.trace('test', service: 'test') do
        Datadog.tracer.trace('test_inner', service: 'test') do
          sleep(0.001)
        end
      end
    end
  end
end

class ThreadRunner
  attr_reader :iterations_count, :conditional_variable

  def initialize(iterations)
    @iterations_count = Concurrent::AtomicFixnum.new(iterations)
    @iterations = iterations
    @conditional_variable = ConditionVariable.new
    @test = if Datadog.respond_to?(:configure)
              Test.new
            else
              TestWithoutDatadog.new
            end
  end

  def prepare
    @threads = []
    @iterations_count = Concurrent::AtomicFixnum.new(@iterations)

    @iterations.times do
      @threads << Thread.new do
        @iterations_count.decrement
        @test.perform
      end
    end
  end

  def await
    @threads.each(&:join)
    conditional_variable.broadcast
  end
end

class BatchRunner
  attr_reader :iterations_count, :conditional_variable

  def initialize(iterations, runner)
    @runner = runner
    @iterations_count = Concurrent::AtomicFixnum.new(iterations)
    @iterations = iterations
    @conditional_variable = ConditionVariable.new
  end

  def prepare
    @iterations_count = Concurrent::AtomicFixnum.new(@iterations)

    @worker = Thread.new do
      while @iterations_count.value > 0
        @iterations_count.decrement

        @runner.prepare
        @runner.await
      end
    end
  end

  def await
    @worker.join
    conditional_variable.broadcast
  end
end

if Datadog.respond_to?(:configure)
  Datadog.configure do |d|
    processor = Datadog::Pipeline::SpanProcessor.new do |span|
      true if span.service == 'B'

    end
    d.use :http

    Datadog::Pipeline.before_flush(processor)
  end
end

def current_memory
  `ps -o rss #{$PROCESS_ID}`.split("\n")[1].to_f / 1024
end

def time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def wait_and_measure(iterations, runner)
  start = time

  STDERR.puts "#{time - start}, #{current_memory}"

  mutex = Mutex.new

  while runner.iterations_count.value > 0
    mutex.synchronize do
      runner.conditional_variable.wait(mutex, 1)
      STDERR.puts "#{time - start}, #{current_memory}"
    end
  end

  yield if block_given?
  STDERR.puts "#{time - start}, #{current_memory}"
end

runner = ThreadRunner.new(TestConfiguration.iteration_count/100)
batch_runner = BatchRunner.new(100, runner)
batch_runner.prepare

wait_and_measure(TestConfiguration.iteration_count, batch_runner) do
  batch_runner.await
  Datadog.tracer.shutdown! if Datadog.respond_to?(:configure)
end

