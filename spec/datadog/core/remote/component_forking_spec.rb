# frozen_string_literal: true

require "spec_helper"
require "datadog/core/remote/component"
require "datadog/core/utils/base64_codec"

RSpec.describe Datadog::Core::Remote::Component do
  forking_platform_only

  reset_at_fork_monkey_patch_for_components!

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.remote.poll_interval_seconds = 60 # Long interval to avoid unnecessary syncs
      # Host may be overridden by environment variables
      settings.agent.host = "localhost"
      settings.agent.port = 9999 # Use a port that won't have an actual agent
    end
  end

  let(:logger) { logger_allowing_debug }

  let(:components) do
    Datadog::Core::Configuration::Components.new(settings)
  end

  let(:component) do
    components.remote
  end

  after do
    component&.shutdown!
  end

  context "when remote config is disabled" do
    before do
      settings.remote.enabled = false
    end

    it "stays disabled in child process" do
      expect(component).to be_nil

      expect_in_fork do
        expect(components.remote).to be_nil
      end
    end
  end

  context "when remote config is enabled" do
    before do
      # after_fork handler goes through the global variable.
      #
      # Cannot use +expect+ here because the call is in child process.
      allow(Datadog).to receive(:components).and_return(components)
    end

    it "is enabled in child process" do
      expect(component).to be_a(Datadog::Core::Remote::Component)
      expect(component.client).to be_a(Datadog::Core::Remote::Client)

      expect_in_fork do
        expect(components.remote).to be_a(Datadog::Core::Remote::Component)
        expect(components.remote.client).to be_a(Datadog::Core::Remote::Client)
      end
    end

    context "when remote config is started" do
      before do
        component.start
      end

      it "recreates client with new ID after fork" do
        parent_client_id = component.client.id
        parent_client_object_id = component.client.object_id

        expect(component.started?).to be true
        expect(parent_client_id).to be_valid_uuid

        expect_in_fork do
          child_component = components.remote

          expect(child_component.started?).to be false

          # Client should be a new instance
          expect(child_component.client.object_id).not_to eq(parent_client_object_id)

          # Client ID should be different
          child_client_id = child_component.client.id
          expect(child_client_id).to be_valid_uuid
          expect(child_client_id).not_to eq(parent_client_id)
        end
      end

      it "resets healthy flag after fork" do
        # Make the component healthy in the parent
        component.instance_variable_set(:@healthy, true)
        expect(component.healthy).to be true

        expect_in_fork do
          child_component = components.remote

          # Healthy flag should be reset to false
          expect(child_component.healthy).to be false
        end
      end

      it "preserves configuration after fork" do
        parent_settings = component.client.settings
        parent_logger = component.logger

        expect_in_fork do
          child_component = components.remote
          child_client = child_component.client

          # Settings and logger should be the same object references
          expect(child_client.settings).to equal(parent_settings)
          expect(child_component.logger).to equal(parent_logger)
        end
      end
    end
  end

  context "network requests after fork", :integration do
    let(:received_requests) { [] }
    let(:request_mutex) { Mutex.new }

    let(:info_handler) do
      lambda do |req, res|
        request_mutex.synchronize do
          received_requests << {endpoint: "/info", method: req.request_method}
        end
        res.status = 200
        res["Content-Type"] = "application/json"
        res.body = JSON.dump(
          {
            version: "1.0",
            endpoints: ["/info", "/v0.7/config"],
            config: {},
          }
        )
      end
    end

    let(:config_handler) do
      lambda do |req, res|
        payload = begin
          JSON.parse(req.body)
        rescue
          {}
        end
        client_id = payload.dig("client", "id")
        runtime_id = payload.dig("client", "client_tracer", "runtime_id")

        request_mutex.synchronize do
          received_requests << {
            endpoint: "/v0.7/config",
            method: req.request_method,
            client_id: client_id,
            runtime_id: runtime_id,
            pid: Process.pid,
          }
        end

        # Return an empty but valid response
        jencode = proc do |obj|
          Datadog::Core::Utils::Base64Codec.strict_encode64(JSON.dump(obj)).chomp
        end

        res.status = 200
        res["Content-Type"] = "application/json"
        res.body = JSON.dump(
          {
            roots: [jencode.call({})],
            targets: jencode.call(
              {
                signed: {
                  expires: "2099-12-31T23:59:59Z",
                  targets: {},
                },
              }
            ),
            target_files: [],
            client_configs: [],
          }
        )
      end
    end

    http_server do |http_server|
      http_server.mount_proc("/info", &info_handler)
      http_server.mount_proc("/v0.7/config", &config_handler)
    end

    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |settings|
        settings.remote.enabled = true
        settings.remote.poll_interval_seconds = 0.1 # Short interval for testing
        settings.remote.boot_timeout_seconds = 5
        settings.agent.host = "localhost"
        settings.agent.port = http_server_port
      end
    end

    before do
      # after_fork handler goes through the global variable.
      allow(Datadog).to receive(:components).and_return(components)
    end

    it "sends requests with different client IDs from parent and child processes" do
      expect(component.barrier(:once)).to eq(:lift)
      expect(component.barrier(:once)).to eq(:pass)
      expect(component.healthy).to be true

      parent_requests = request_mutex.synchronize do
        received_requests.select { |r| r[:endpoint] == "/v0.7/config" }
      end
      expect(parent_requests).not_to be_empty

      parent_client_id = parent_requests.first[:client_id]
      parent_runtime_id = parent_requests.first[:runtime_id]
      expect(parent_client_id).to be_valid_uuid
      expect(parent_runtime_id).to be_valid_uuid

      reader, writer = IO.pipe
      begin
        expect_in_fork do
          reader.close
          child_component = components.remote
          expect(child_component).not_to be_started
          expect(child_component.healthy).to be false
          expect(Thread.list.map(&:name)).not_to include(Datadog::Core::Remote::Worker.name)

          expect(child_component.barrier(:once)).to eq(:lift)
          expect(child_component.healthy).to be true
          expect(child_component.barrier(:once)).to eq(:pass)

          writer.write(JSON.dump(
            client_id: child_component.client.id,
            runtime_id: Datadog::Core::Environment::Identity.id,
          ))
        ensure
          child_component&.shutdown!
          writer.close
        end

        writer.close
        child = JSON.parse(reader.read, symbolize_names: true)
        expect(child[:client_id]).to be_valid_uuid
        expect(child[:client_id]).not_to eq(parent_client_id)
        expect(child[:runtime_id]).to be_valid_uuid
        expect(child[:runtime_id]).not_to eq(parent_runtime_id)

        child_requests = request_mutex.synchronize do
          received_requests.select { |r| r[:endpoint] == "/v0.7/config" && r[:client_id] == child[:client_id] }
        end
        expect(child_requests).not_to be_empty
        expect(child_requests).to all(include(runtime_id: child[:runtime_id]))
        expect(component).to be_started
        expect(component.client.id).to eq(parent_client_id)
        expect(component.barrier(:once)).to eq(:pass)
      ensure
        reader.close
        writer.close unless writer.closed?
      end
    end

    it "recreates client instance after fork with network verification" do
      parent_client = component.client
      parent_client_object_id = parent_client.object_id
      parent_client_id = parent_client.id

      expect_in_fork do
        child_component = components.remote
        child_client = child_component.client

        # Should be a different object
        expect(child_client.object_id).not_to eq(parent_client_object_id)

        # Should have a different ID
        expect(child_client.id).not_to eq(parent_client_id)

        # Should have fresh state
        expect(child_component.healthy).to be false
      end
    end
  end
end
