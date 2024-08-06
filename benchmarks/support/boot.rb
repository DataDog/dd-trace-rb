require 'forwardable'

# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

class MiddlewareStack
  def initialize
    @stack = []
  end

  def before(&block)
    @stack << [:before, block]
  end

  def after(&block)
    @stack << [:after, block]
  end

  def around(&block)
    @stack << [:around, block]
  end

  def call(&block)
    do_call(@stack, &block)
  end

  private

  def do_call(stack, &block)
    kind, proc = stack.first
    case kind
    when :before
      proc.call
      do_call(stack[1..], &block)
    when :after
      do_call(stack[1..], &block)
      proc.call
    when :around
      proc.call do
        do_call(stack[1..], &block)
      end
    end
  end
end

class Benchmarker
  extend Forwardable

  def initialize(source_file)
    @source_file = source_file
    @middlewares = MiddlewareStack.new
    @benchmarks = []
    @default_benchmark_time = 10
  end

  attr_reader :source_file
  attr_reader :middlewares
  attr_reader :benchmarks

  def_delegators :middlewares, :before, :after, :around

  def default_benchmark_time(*args)
    if args.any?
      if args.length > 1
        raise ArgumentError, 'Zero or one arguments are required'
      end
      @default_benchmark_time = args.first
    else
      @default_benchmark_time
    end
  end

  def source_file_without_ext
    source_file.sub(/\.rb\z/, '')
  end

  def benchmark(name, time: nil, &block)
    benchmarks << lambda do
      Benchmark.ips do |x|
        _benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: time || default_benchmark_time, warmup: 2 }
        x.config(
          **_benchmark_time,
          suite: suite_for_dogstatsd_reporting(benchmark_name: source_file_without_ext)
        )

        x.report(name, &block)

        x.save! "#{source_file_without_ext}-results.json" unless VALIDATE_BENCHMARK_MODE
        x.compare!
      end
    end
  end

  def report_pid
    puts "Current pid is #{Process.pid}"
  end

  def run
    forever = ARGV.include?('--forever')
    if forever && !respond_to?(:run_forever)
      raise "Benchmark does not define run_forever method"
    end

    report_pid

    middlewares.call do
      if forever
        # run_forever does not normally return thus the "after" hooks
        # will not be invoked.
        run_forever
      else
        run_benchmarks
      end
    end
  end

  def run_benchmarks
    benchmarks.map(&:call)
  end

  class << self
    def define(&block)
      caller_path = caller_locations.first.path

      return unless caller_path == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

      require 'benchmark/ips'
      require 'datadog'
      require 'pry'
      require_relative 'dogstatsd_reporter'

      # Create a new class so that methods can delegate to the base
      # implementation via super.
      cls_name = File.basename(caller_path).sub(/\.rb\z/, '').gsub(/_(\w)/) { |m| m[1..].upcase }.gsub(/\A(.)/) { |m| m.upcase }
      cls = Class.new(self).new(caller_path)
      Object.const_set(cls_name, cls)
      cls.instance_exec(&block)
      cls.run
    end
  end

  REPORTING_DISABLED_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new

  def suite_for_dogstatsd_reporting(**args)
    if ENV['REPORT_TO_DOGSTATSD'] == 'true'
      puts "DogStatsD reporting ✅ enabled"
      require_relative 'dogstatsd_reporter'
      DogstatsdReporter.new(**args)
    else
      REPORTING_DISABLED_ONLY_ONCE.run { puts "DogStatsD reporting ❌ disabled" }
      nil
    end
  end
end
