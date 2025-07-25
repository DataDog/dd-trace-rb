# Used to quickly run benchmark under RSpec as part of the usual test suite, to validate it didn't bitrot
VALIDATE_BENCHMARK_MODE = ENV['VALIDATE_BENCHMARK'] == 'true'

return unless __FILE__ == $PROGRAM_NAME || VALIDATE_BENCHMARK_MODE

require_relative 'benchmarks_helper'
require 'securerandom'
require 'socket'

# This benchmark measures the performance of the http_transport class used for reporting profiling data
#
# Note when running on macOS: If the benchmark starts failing with a timeout after around ~16k requests, try
# lowering the timeout for keeping ports in the TIME_WAIT state by using `sudo sysctl -w net.inet.tcp.msl=1`.
#
# The default on my machine is 15000 (15 seconds) which trips this bug quite easily.
# This doesn't seem to be clearly documented anywhere, you just see people rediscovering it on the web, for instance
# in https://gist.github.com/carlos8f/3473107 . If you're curious, the ports show up using the `netstat` tool.
# Behavior on Linux seems to be different (or at least the defaults are way higher).

class ProfilerHttpTransportBenchmark
  def initialize
    raise(Datadog::Profiling.unsupported_reason) unless Datadog::Profiling.supported?

    @port = 6006
    start_fake_webserver

    agent_settings_cls = begin
      Datadog::Core::Configuration::AgentSettings
    rescue NameError
      # Compatibility branch, delete after
      # https://github.com/DataDog/dd-trace-rb/pull/4741 is merged.
      Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings
    end

    @transport = Datadog::Profiling::HttpTransport.new(
      agent_settings: agent_settings_cls.new(
        adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
        uds_path: nil,
        ssl: false,
        hostname: '127.0.0.1',
        port: @port,
        timeout_seconds: nil,
      ),
      site: nil,
      api_key: nil,
      upload_timeout_seconds: 10,
    )
    @flush_finish = Time.now.utc
    @stack_recorder = Datadog::Profiling::StackRecorder.for_testing
  end

  def flush
    Datadog::Profiling::Flush.new(
      start: @flush_finish - 60,
      finish: @flush_finish,
      encoded_profile: @stack_recorder.serialize!,
      code_provenance_file_name: 'example_code_provenance_file_name.json',
      code_provenance_data: '',
      tags_as_array: [],
      internal_metadata: { no_signals_workaround_enabled: false },
      info_json: JSON.generate({ profiler: { benchmarking: true } }),
    )
  end

  def start_fake_webserver
    ready_queue = Queue.new

    Thread.new do
      server = TCPServer.new(@port || raise('Missing port'))

      ready_queue << true

      loop do
        client = server.accept
        loop do
          line = client.gets
          break if line.end_with?("--\r\n")
        end
        client.write("HTTP/1.0 200 OK\nConnection: close\n\n")
        client.close
      end
    end

    ready_queue.pop
  end

  def run_benchmark
    Benchmark.ips do |x|
      benchmark_time = VALIDATE_BENCHMARK_MODE ? { time: 0.01, warmup: 0 } : { time: 70, warmup: 2 }
      x.config(
        **benchmark_time,
      )

      x.report("http_transport #{ENV['CONFIG']}") do
        run_once
      end

      x.save! "#{File.basename(__FILE__)}-results.json" unless VALIDATE_BENCHMARK_MODE
      x.compare!
    end
  end

  def run_once
    success = @transport.export(flush)

    raise('Unexpected: Export failed') unless success
  end
end

puts "Current pid is #{Process.pid}"

ProfilerHttpTransportBenchmark.new.instance_exec do
  run_benchmark
end
