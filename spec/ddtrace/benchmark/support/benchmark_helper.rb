require 'spec_helper'

require 'datadog/statsd'
require 'ddtrace'

require 'benchmark/ips'
if !PlatformHelpers.jruby? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
  require 'benchmark/memory'
  require 'memory_profiler'
end

require 'fileutils'
require 'json'

RSpec.shared_context 'benchmark' do
  # When applicable, runs the test subject for different input sizes.
  # Similar to how N in Big O notation works.
  #
  # This value is provided to the `subject(i)` method in order for the test
  # to appropriately execute its run based on input size.
  let(:steps) { defined?(super) ? super() : [1, 10, 100] }

  # How many times we run our program when testing for memory allocation.
  # In theory, we should only need to run it once, as memory tests are not
  # dependent on competing system resources.
  # But occasionally we do see a few blimps of inconsistency, making the benchmarks skewed.
  # By running the benchmarked snippet many times, we drown out any one-off anomalies, allowing
  # the real memory culprits to surface.
  let(:memory_iterations) { defined?(super) ? super() : 100 }

  # How long the program will run when calculating IPS performance, in seconds.
  let(:timing_runtime) { defined?(super) ? super() : 5 }

  # Outputs human readable information to STDERR.
  # Most of the benchmarks have nicely formatted reports
  # that are by default printed to terminal.
  before do |e|
    @test = e.metadata[:example_group][:full_description]
    @type = e.description

    STDERR.puts "Test:#{e.metadata[:example_group][:full_description]} #{e.description}"
  end

  def warm_up
    steps.each do |s|
      subject(s)
    end
  end

  # Report JSON result objects to ./tmp/benchmark/ folder
  # Theses results can be historically tracked (e.g. plotting) if needed.
  def write_result(result, subtype = nil)
    file_name = if subtype
                  "#{@type}-#{subtype}"
                else
                  @type
                end

    STDERR.puts(@test, file_name, result)

    directory = result_directory!(subtype)
    path = File.join(directory, file_name)

    File.write(path, JSON.pretty_generate(result))

    STDERR.puts("Result written to #{path}")
  end

  # Create result directory for current benchmark
  def result_directory!(subtype = nil)
    path = File.join('tmp', 'benchmark', @test)
    path = File.join(path, subtype.to_s) if subtype

    FileUtils.mkdir_p(path)

    path
  end

  # Measure execution time
  it 'timing' do
    report = Benchmark.ips do |x|
      x.config(time: timing_runtime, warmup: timing_runtime / 10.0)

      steps.each do |s|
        x.report(s) do
          subject(s)
        end
      end

      x.compare!
    end

    result = report.entries.each_with_object({}) do |entry, hash|
      hash[entry.label] = { ips: entry.stats.central_tendency, error: entry.stats.error_percentage / 100 }
    end.to_h

    write_result(result)
  end

  # Measure memory usage (object creation and memory size)
  it 'memory' do
    warm_up

    if PlatformHelpers.jruby? || Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
      skip("'benchmark/memory' not supported")
    end

    report = Benchmark.memory do |x|
      steps.each do |s|
        x.report(s) do
          memory_iterations.times { subject(s) }
        end
      end

      x.compare!
    end

    result = report.entries.map do |entry|
      row = entry.measurement.map do |metric|
        { type: metric.type, allocated: metric.allocated, retained: metric.retained }
      end

      [entry.label, row]
    end.to_h

    write_result(result)
  end

  # Measure GC cycles triggered during run
  it 'gc' do
    skip if PlatformHelpers.jruby?

    warm_up

    io = StringIO.new
    GC::Profiler.enable

    memory_iterations.times { subject(steps[0]) }

    GC.disable # Prevent data collection from influencing results

    data = GC::Profiler.raw_data
    GC::Profiler.report(io)
    GC::Profiler.disable

    GC.enable

    puts io.string

    result = { count: data.size, time: data.map { |d| d[:GC_TIME] }.inject(0, &:+) }
    write_result(result)
  end

  # Reports that generate non-aggregated data.
  # Useful for debugging.
  context 'detailed' do
    before { skip('Detailed report are too verbose for CI') if ENV.key?('CI') }

    let(:ignore_files) { defined?(super) ? super() : nil }

    # Memory report with reference to each allocation site
    it 'memory report' do
      if PlatformHelpers.jruby? || Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
        skip("'benchmark/memory' not supported")
      end

      warm_up

      steps.each do |step|
        report = MemoryProfiler.report(ignore_files: ignore_files) do
          memory_iterations.times { subject(step) }
        end

        report_results(report, step)
      end
    end

    def report_results(report, step)
      puts "Report for step: #{step}"
      report.pretty_print

      per_gem_report = lambda do |results|
        Hash[results.map { |x| [x[:data], x[:count]] }.sort_by(&:first)]
      end

      result = {
        total_allocated: report.total_allocated,
        total_allocated_memsize: report.total_allocated_memsize,
        total_retained: report.total_retained,
        total_retained_memsize: report.total_retained_memsize,
        allocated_memory_by_gem: per_gem_report[report.allocated_memory_by_gem],
        allocated_objects_by_gem: per_gem_report[report.allocated_objects_by_gem],
        retained_memory_by_gem: per_gem_report[report.retained_memory_by_gem],
        retained_objects_by_gem: per_gem_report[report.retained_objects_by_gem]
      }
      write_result(result, step)
    end

    # CPU profiling report
    context 'RubyProf report' do
      before do
        if PlatformHelpers.jruby? || Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
          skip("'ruby-prof' not supported")
        end
      end

      before do
        require 'ruby-prof'
        RubyProf.measure_mode = RubyProf::PROCESS_TIME
      end

      it do
        warm_up

        steps.each do |step|
          result = RubyProf.profile do
            (memory_iterations * 5).times { subject(step) }
          end

          report_results(result, step)
        end
      end

      def report_results(result, step)
        puts "Report for step: #{step}"

        directory = result_directory!(step)

        printer = RubyProf::CallTreePrinter.new(result)
        printer.print(path: directory)

        STDERR.puts("Results written in Callgrind format to #{directory}")
        STDERR.puts('You can use KCachegrind or QCachegrind to read these results.')
        STDERR.puts('On MacOS:')
        STDERR.puts('$ brew install qcachegrind')
        STDERR.puts("$ qcachegrind '#{Dir["#{directory}/*"].sort[0]}'")
      end
    end
  end
end

require 'socket'

# An "agent" that always responds with a proper OK response, while
# keeping minimum overhead.
#
# The goal is to reduce external performance noise from running a real
# agent process in the system.
#
# It finds a locally available port to listen on, and updates the value of
# {Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} accordingly.
RSpec.shared_context 'minimal agent' do
  let(:agent_server) { TCPServer.new '127.0.0.1', agent_port }
  let(:agent_port) { ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT].to_i }

  # Sample agent response, collected from a real agent exchange.
  AGENT_HTTP_RESPONSE = "HTTP/1.1 200\r\n" \
    "Content-Length: 40\r\n" \
    "Content-Type: application/json\r\n" \
    "Date: Thu, 03 Sep 2020 20:05:54 GMT\r\n" \
    "\r\n" \
    "{\"rate_by_service\":{\"service:,env:\":1}}\n".freeze

  def server_runner
    previous_conn = nil
    loop do
      conn = agent_server.accept
      conn.print AGENT_HTTP_RESPONSE
      conn.flush

      # Read HTTP request to allow other side to have enough
      # buffer write room. If we don't, the client won't be
      # able to send the full request until the buffer is cleared.
      conn.read(1 << 31 - 1)

      # Closing the connection immediately can sometimes
      # be too fast, cause to other side to not be able
      # to read the response in time.
      # We instead delay closing the connection until the next
      # connection request comes in.
      previous_conn.close if previous_conn
      previous_conn = conn
    end
  end

  before do
    # Initializes server in a fork, to allow for true concurrency.
    # In JRuby, threads are not supported, but true thread concurrency is.
    @agent_runner = if PlatformHelpers.supports_fork?
                      fork { server_runner }
                    else
                      Thread.new { server_runner }
                    end
  end

  after do
    if PlatformHelpers.supports_fork?
      Process.kill('TERM', @agent_runner) rescue nil
      Process.wait(@agent_runner)
    else
      @agent_runner.kill
    end
  end

  around do |example|
    # Set the agent port used by the default HTTP transport
    ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT => available_port.to_s) do
      example.run
    end
  end
end
