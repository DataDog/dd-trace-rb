# frozen_string_literal: true

# Runs one telemetry backend parity scenario and prints the wire report as
# JSON on stdout. Launched as a fresh process by backend_parity_spec.rb,
# so the native worker runs in the same conditions as a real application:
# a forking child that builds the native worker inherits a broken tokio
# runtime from the parent process.
#
# Arguments: <native_worker true|false> <scenario name>
# Requires DD_TELEMETRY_HEARTBEAT_INTERVAL in the environment.

require "bundler/setup"
require "socket"
require "json"
require "datadog"

# Capturing mock agent: runs in a fork, writes captured telemetry bodies
# to a pipe. A separate process keeps the agent accepting while the main
# thread blocks in the native shutdown call.
class FakeAgent
  attr_reader :port

  def initialize
    @read_io, @write_io = IO.pipe
    server = TCPServer.new("127.0.0.1", 0)
    @port = server.addr[1]

    @pid = fork do
      @read_io.close
      http_response = "HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\n" \
                      "Content-Type: application/json\r\n\r\n{}"
      mutex = Mutex.new
      loop do
        client = begin
          server.accept
        rescue
          break
        end
        Thread.new(client) do |c|
          request_line = c.gets
          next c.close if request_line.nil?
          path = request_line.split(" ")[1]
          headers = {}
          while (line = c.gets) && line != "\r\n"
            key, value = line.split(":", 2)
            headers[key.downcase] = value.strip
          end
          content_length = headers.fetch("content-length", "0").to_i
          request_body = content_length.positive? ? c.read(content_length) : ""
          c.print http_response
          next unless path&.include?("apmtelemetry")
          payload = Marshal.dump(body: request_body)
          mutex.synchronize do
            @write_io.write([payload.bytesize].pack("N"))
            @write_io.write(payload)
            @write_io.flush
          end
        rescue # rubocop:disable Lint/SuppressedException
        ensure
          begin
            c.close
          rescue
            nil
          end
        end
      end
      server.close
      @write_io.close
    end
    server.close
  end

  # Drains the pipe. After each read it waits up to +timeout+ for more data.
  def read_requests(timeout: 1)
    requests = []
    while IO.select([@read_io], nil, nil, timeout)
      len_bytes = @read_io.read(4)
      break if len_bytes.nil? || len_bytes.bytesize < 4

      len = len_bytes.unpack1("N")
      requests << JSON.parse(Marshal.load(@read_io.read(len))[:body]) # rubocop:disable Security/MarshalLoad
    end
    requests
  end

  def stop
    Process.kill("TERM", @pid)
  rescue
    nil
  ensure
    begin
      Process.wait(@pid)
    rescue
      nil
    end
    begin
      @read_io.close unless @read_io.closed?
    rescue
      nil
    end
  end
end

def run_scenario(name, component)
  case name
  when "metrics"
    component.inc("tracers", "parity.inc", 5, tags: ["src_library:parity"])
    component.inc("tracers", "parity.inc", 3, tags: {"src_library" => "parity"})
    component.dec("tracers", "parity.dec", 2)
    component.gauge("tracers", "parity.gauge", 42.5)
    component.rate("tracers", "parity.rate", 7)
    component.distribution("tracers", "parity.dist", 123)
  when "logs"
    3.times { component.log!(Datadog::Core::Telemetry::Event::Log.new(message: "parity repeated", level: :error)) }
    component.log!(Datadog::Core::Telemetry::Event::Log.new(message: "parity distinct", level: :warn))
  when "lifecycle"
    component.client_configuration_change!({"appsec.enabled" => true})
    component.app_endpoints_loaded([
      {type: "REST", method: "GET", path: "/parity", operation_name: "parity.request", resource_name: "GET /parity"},
    ])
  else
    raise ArgumentError, "Unknown scenario: #{name}"
  end
end

agent = FakeAgent.new
Datadog.configure do |c|
  c.agent.host = "127.0.0.1"
  c.agent.port = agent.port
  c.telemetry.enabled = true
  c.telemetry.native_worker = (ARGV[0] == "true")
  c.service = "parity-svc"
end
component = Datadog.send(:components).telemetry
run_scenario(ARGV[1], component)
# Two heartbeat beats, so the native worker flushes the scenario's metrics
# and logs before the shutdown cancel deadline cuts the final POST in flight.
# Pending data flushes on heartbeat beats only: the stop flush sends
# app-closing.
sleep 5
component.backend.flush
# The full components shutdown is the production exit path: it enqueues
# app-closing (the telemetry component shutdown alone does not) and flushes
# it through the backend.
Datadog.send(:components).shutdown!
sleep 1 # both backends deliver the final flush asynchronously
requests = agent.read_requests
report = {backend: component.backend.class.name, requests: requests}
agent.stop
# The last stdout line is the report.
puts report.to_json
