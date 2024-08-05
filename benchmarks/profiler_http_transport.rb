require_relative 'support/boot'

# This benchmark measures the performance of the http_transport class used for reporting profiling data
#
# Note when running on macOS: If the benchmark starts failing with a timeout after around ~16k requests, try
# lowering the timeout for keeping ports in the TIME_WAIT state by using `sudo sysctl -w net.inet.tcp.msl=1`.
#
# The default on my machine is 15000 (15 seconds) which trips this bug quite easily.
# This doesn't seem to be clearly documented anywhere, you just see people rediscovering it on the web, for instance
# in https://gist.github.com/carlos8f/3473107 . If you're curious, the ports show up using the `netstat` tool.
# Behavior on Linux seems to be different (or at least the defaults are way higher).
Benchmarker.define do
  require 'securerandom'
  require 'socket'

  before do
    raise(Datadog::Profiling.unsupported_reason) unless Datadog::Profiling.supported?

    @port = 6006
    start_fake_webserver

    @transport = Datadog::Profiling::HttpTransport.new(
      agent_settings: Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
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
    flush_finish = Time.now.utc
    @flush = Datadog::Profiling::Flush.new(
      start: flush_finish - 60,
      finish: flush_finish,
      pprof_file_name: 'example_pprof_file_name.pprof',
      pprof_data: '', # Random.new(0).bytes(32_000),
      code_provenance_file_name: 'example_code_provenance_file_name.json',
      code_provenance_data: '', # Random.new(1).bytes(4_000),
      tags_as_array: [],
      internal_metadata: { no_signals_workaround_enabled: false },
      info_json: JSON.fast_generate({ profiler: { benchmarking: true } }),
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

  benchmark("http_transport #{ENV['CONFIG']}", time: 70) do
    success = @transport.export(@flush)

    raise('Unexpected: Export failed') unless success
  end

  def run_forever
    loop do
      100.times { run_benchmarks }
      print '.'
    end
  end
end
