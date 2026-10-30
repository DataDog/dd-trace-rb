require "datadog/profiling/spec_helper"
require "datadog/profiling/remote"
require "digest"

# Drives the real remote configuration client against a fake agent, and checks that the real profiler
# starts, stops and restarts accordingly. Syncs are triggered directly instead of through the polling
# worker, so every step completes before the next one.
RSpec.describe "Profiling remote configuration", :memcheck_valgrind_skip do
  let(:config_path) { "datadog/2/DEBUG/preset-default/config" }
  let!(:config_requests) { Queue.new }
  let!(:profile_uploads) { Queue.new }
  let(:target) { {service: "rc-test", env: "test"} }
  let(:worker_thread_name) { Datadog::Profiling::Collectors::CpuAndWallTimeWorker.name }

  http_server do |http_server|
    http_server.mount_proc("/info") do |_req, res|
      res.body = JSON.dump(endpoints: ["/v0.7/config", "/profiling/v1/input"])
    end
    http_server.mount_proc("/v0.7/config") do |req, res|
      request = JSON.parse(req.body)
      config_requests << request
      res.body = config_response(request.dig("client", "state", "targets_version"))
    end
    http_server.mount_proc("/profiling/v1/input") do |req, res|
      profile_uploads << req.body
      res.body = "{}"
    end
    http_server.mount_proc("/") do |_req, res|
      res.body = "{}"
    end
  end

  # Mirrors the agent: an empty response while the client is up to date, otherwise the current config.
  def config_response(client_targets_version)
    version = @rc_version || 0
    return "{}" if client_targets_version == version

    targets = {}
    if @rc_payload
      targets[config_path] = {
        custom: {v: version},
        hashes: {sha256: Digest::SHA256.hexdigest(@rc_payload)},
        length: @rc_payload.bytesize,
      }
    end

    JSON.dump(
      roots: [],
      targets: Datadog::Core::Utils::Base64Codec.strict_encode64(JSON.dump(signed: {targets: targets, version: version})),
      target_files: @rc_payload ? [{path: config_path, raw: Datadog::Core::Utils::Base64Codec.strict_encode64(@rc_payload)}] : [],
      client_configs: @rc_payload ? [config_path] : [],
    )
  end

  def deliver(payload)
    @rc_payload = payload && JSON.dump(payload)
    @rc_version = (@rc_version || 0) + 1
  end

  def sync_remote_config
    Datadog.send(:components).remote.client.sync
  end

  def last_config_request
    Array.new(config_requests.size) { config_requests.pop }.last
  end

  def enable_profiling(settings: {})
    deliver(profilers: {cpuTime: true, wallTime: true}, settings: settings, targets: [target])
    sync_remote_config
    expect(Datadog::Profiling.wait_until_running).to be true
  end

  before do
    skip_if_profiling_not_supported

    # Keep the profiler's process-wide monkey patches out of the RSpec process.
    allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(instance_double(Datadog::Profiling::Tasks::Setup, run: nil))
    allow(Datadog::Profiling::Ext::DirMonkeyPatches).to receive(:apply!).and_return(true)
    # Report the last profile on shutdown even though each profiler only runs briefly.
    stub_const("Datadog::Profiling::Exporter::PROFILE_DURATION_THRESHOLD_SECONDS", 0)

    Datadog.configure do |c|
      c.service = "rc-test"
      c.env = "test"
      c.agent.host = "127.0.0.1"
      c.agent.port = http_server_port
      c.remote.enabled = true
      c.telemetry.enabled = false
      c.crashtracking.enabled = false
      c.profiling.advanced.shutdown_on_exec_enabled = false
    end
  end

  # Before the fake agent shuts down, so the last profile has somewhere to go.
  after { Datadog.shutdown! }

  it "starts the profiler, disabled by default, when profiling is enabled remotely" do
    sync_remote_config

    expect(last_config_request.dig("client", "products")).to include("DEBUG")
    expect(Datadog.send(:components).profiler).to be_nil

    enable_profiling

    expect(Datadog.configuration.profiling.enabled).to be true
  end

  it "reports the config as applied in the next request" do
    enable_profiling
    sync_remote_config

    expect(last_config_request.dig("client", "state", "config_states")).to contain_exactly(
      include("id" => "preset-default", "product" => "DEBUG", "apply_state" => 2)
    )
  end

  it "stops the profiler and reports the last profile when profiling is disabled remotely" do
    enable_profiling

    deliver(profilers: {cpuTime: false, wallTime: false, heapSize: false, allocations: false}, targets: [target])
    sync_remote_config

    expect(Datadog.send(:components).profiler).to be_nil
    expect(Thread.list.map(&:name)).to_not include(worker_thread_name)
    expect(profile_uploads.size).to eq(1)
    expect(profile_uploads.pop).to include("profile.pprof")
  end

  it "restarts the profiler when a setting changes while it runs" do
    enable_profiling(settings: {rubySignalWorkaround: true})
    old_profiler = Datadog.send(:components).profiler

    deliver(profilers: {cpuTime: true, wallTime: true}, settings: {rubySignalWorkaround: false}, targets: [target])
    sync_remote_config

    expect(Datadog.configuration.profiling.advanced.no_signals_workaround_enabled).to be false
    expect(Datadog.send(:components).profiler).to_not be(old_profiler)
    expect(Datadog::Profiling.wait_until_running).to be true
    expect(Thread.list.map(&:name).count(worker_thread_name)).to eq(1)
    expect(profile_uploads.size).to eq(1)
  end

  it "stops the profiler and restores the local configuration when the config is removed" do
    enable_profiling

    deliver(nil)
    sync_remote_config

    expect(Datadog.send(:components).profiler).to be_nil
    expect(Datadog.configuration.profiling.enabled).to be false
  end
end
