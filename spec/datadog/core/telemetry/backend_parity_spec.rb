# frozen_string_literal: true

require "spec_helper"

require "datadog/core/telemetry/component"
require "datadog/core/telemetry/event/log"
require "socket"
require "json"

# Wire-level parity between the Ruby and Native telemetry backends.
#
# Each backend runs the same scenario in a forked child process against a
# capturing mock agent, like the native transport conformance specs.
# The child reports its backend class and the parsed request bodies, so a
# silent fallback to the Ruby backend fails loudly instead of passing.
#
# Payloads are normalized to a backend-independent shape (timestamps,
# aggregation intervals, and sketch encoding are backend-specific) and
# compared against explicit expectations shared by both backends.
RSpec.describe "Telemetry backend wire parity" do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:metrics_scenario) do
    lambda do |component|
      component.inc("tracers", "parity.inc", 5, tags: ["src_library:parity"])
      component.inc("tracers", "parity.inc", 3, tags: {"src_library" => "parity"})
      component.dec("tracers", "parity.dec", 2)
      component.gauge("tracers", "parity.gauge", 42.5)
      component.rate("tracers", "parity.rate", 7)
      component.distribution("tracers", "parity.dist", 123)
    end
  end

  let(:logs_scenario) do
    lambda do |component|
      3.times { component.log!(Datadog::Core::Telemetry::Event::Log.new(message: "parity repeated", level: :error)) }
      component.log!(Datadog::Core::Telemetry::Event::Log.new(message: "parity distinct", level: :warn))
    end
  end

  let(:expected_metrics) do
    {
      "parity.inc" => {"type" => "count", "tags" => ["src_library:parity"], "value_sum" => 8.0, "namespace" => "tracers"},
      "parity.dec" => {"type" => "count", "tags" => [], "value_sum" => -2.0, "namespace" => "tracers"},
      "parity.gauge" => {"type" => "gauge", "tags" => [], "value_sum" => 42.5, "namespace" => "tracers"},
      "parity.rate" => {"type" => "rate", "tags" => [], "namespace" => "tracers"},
    }
  end

  let(:expected_distributions) do
    [
      {"metric" => "parity.dist", "tags" => [], "namespace" => "tracers"},
    ]
  end

  # Thread-based capturing agent, runs inside the forked child.
  class FakeAgent # rubocop:disable Lint/ConstantDefinitionInBlock
    attr_reader :port, :requests

    def initialize
      @requests = []
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { accept_loop }
    end

    def stop
      @server.close
      @thread.join(2)
    rescue
      nil
    end

    private

    def accept_loop
      while (client = @server.accept)
        handle(client)
      end
    rescue
      nil
    end

    def handle(client)
      request_line = client.gets
      return client.close if request_line.nil?

      headers = {}
      while (line = client.gets) && line != "\r\n"
        key, value = line.split(": ", 2)
        headers[key.downcase] = value&.strip
      end
      length = (headers["content-length"] || 0).to_i
      body = length.positive? ? client.read(length) : ""
      @requests << {path: request_line.split(" ")[1], body: body}
      client.print "HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\nContent-Type: application/json\r\n\r\n{}"
    rescue
      nil
    ensure
      begin
        client.close
      rescue
        nil
      end
    end
  end

  def wire_data(native_worker:, scenario:)
    @wire_data ||= {}
    @wire_data[[native_worker, scenario]] ||= run_child(native_worker: native_worker, scenario: scenario)
  end

  # Runs the scenario in a forked process and returns its reported wire
  # data: {"backend" => class name, "requests" => parsed bodies} or
  # {"error" => message}.
  def run_child(native_worker:, scenario:)
    out_read, out_write = IO.pipe
    pid = fork do
      out_read.close
      $stdout.reopen(out_write)
      out_write.close
      $stderr.reopen(File::NULL)
      puts child_report(native_worker: native_worker, scenario: scenario).to_json
      exit!(0)
    end
    out_write.close
    last_line = out_read.read.lines.reverse.find { |line| line.start_with?("{") }
    Process.wait(pid)
    JSON.parse(last_line.to_s)
  end

  def child_report(native_worker:, scenario:)
    ENV["DD_TELEMETRY_HEARTBEAT_INTERVAL"] = "2"
    agent = FakeAgent.new
    Datadog.configure do |c|
      c.agent.host = "127.0.0.1"
      c.agent.port = agent.port
      c.telemetry.enabled = true
      c.telemetry.native_worker = native_worker
      c.service = "parity-svc"
    end
    component = Datadog.send(:components).telemetry
    scenario.call(component)
    component.shutdown!
    sleep 1 # both backends deliver the final flush asynchronously

    {
      "backend" => component.backend.class.name,
      "requests" => agent.requests.select { |r| r[:path].include?("apmtelemetry") }.map { |r| JSON.parse(r[:body]) },
    }
  rescue => e
    {"error" => "#{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"}
  end

  # Flattens message-batches and normalizes each entry into a shape that
  # is comparable across backends.
  def normalize(requests)
    metrics = {}
    distributions = []
    logs = []
    lifecycle = []
    entries = requests.flat_map { |body| (body["request_type"] == "message-batch") ? body["payload"] : [body] }
    entries.each do |entry|
      case entry["request_type"]
      when "generate-metrics"
        payload = entry["payload"]
        payload["series"].each do |series|
          metrics[series["metric"]] = {
            "type" => series["type"],
            "tags" => series["tags"].sort,
            "namespace" => series["namespace"] || payload["namespace"],
            "value_sum" => series["points"].sum { |point| point[1].to_f },
          }
        end
      when "distributions", "sketches"
        payload = entry["payload"]
        payload["series"].each do |series|
          distributions << {
            "metric" => series["metric"],
            "tags" => series["tags"].sort,
            "namespace" => series["namespace"] || payload["namespace"],
          }
        end
      when "logs"
        entry["payload"]["logs"].each do |log|
          logs << {"message" => log["message"], "count" => log["count"], "level" => log["level"]}
        end
      else
        lifecycle << entry["request_type"]
      end
    end
    {
      "metrics" => metrics,
      "distributions" => distributions.sort_by { |d| d["metric"] },
      "logs" => logs.sort_by { |l| l["message"] },
      "lifecycle" => lifecycle.sort,
    }
  end

  def normalized(native_worker:, scenario:)
    data = wire_data(native_worker: native_worker, scenario: scenario)
    expect(data["error"]).to be_nil, "child process failed: #{data["error"]}"
    expected_backend = native_worker ? "Datadog::Core::Telemetry::NativeBackend" : "Datadog::Core::Telemetry::RubyBackend"
    expect(data["backend"]).to eq(expected_backend)
    normalize(data["requests"])
  end

  shared_examples "metrics scenario parity" do |native_worker:|
    let(:wire) { normalized(native_worker: native_worker, scenario: metrics_scenario) }

    it "sends the same generate-metrics series" do
      # The rate value_sum is backend-specific (Ruby divides by the
      # aggregation interval) and covered by its own example below.
      actual = wire["metrics"].each_value { |m| m.delete("value_sum") if m["type"] == "rate" }
      expect(actual).to eq(expected_metrics)
    end

    it "sends the same metric values, except rate" do
      expected_values = {"parity.inc" => 8.0, "parity.dec" => -2.0, "parity.gauge" => 42.5}
      expected_values.each { |metric, value| expect(wire["metrics"][metric]["value_sum"]).to eq(value) }
    end

    it "sends the same distribution metric identity" do
      expect(wire["distributions"]).to eq(expected_distributions)
    end

    it "sends lifecycle events through the shared event layer" do
      expect(wire["lifecycle"]).to include("app-started")
    end

    it "submits rate values in backend-specific units" do
      # RubyBackend divides by the metrics aggregation interval (10s):
      # 7 / 10 = 0.7. NativeBackend submits the raw value: 7.0.
      # Divergence tracked in telemetry-migration-progress.md.
      value = wire["metrics"]["parity.rate"]["value_sum"]
      expect(value).to eq(native_worker ? 7.0 : 0.7)
    end
  end

  shared_examples "logs scenario parity" do |native_worker:|
    let(:wire) { normalized(native_worker: native_worker, scenario: logs_scenario) }

    it "deduplicates repeated logs with counts" do
      submitted = wire["logs"].select { |l| l["message"].start_with?("parity") }
      expect(submitted).to eq(
        [
          {"message" => "parity distinct", "count" => 1, "level" => "WARN"},
          {"message" => "parity repeated", "count" => 3, "level" => "ERROR"},
        ],
      )
    end
  end

  [false, true].each do |native_worker|
    backend = native_worker ? "native" : "ruby"

    describe "with the #{backend} backend" do
      it_behaves_like "metrics scenario parity", native_worker: native_worker
      it_behaves_like "logs scenario parity", native_worker: native_worker
    end
  end
end
