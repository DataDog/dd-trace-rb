# frozen_string_literal: true

require "msgpack"
require "google/protobuf"
require "open3"
require "rbconfig"
require "spec_helper"
require "datadog/core/process_discovery"

RSpec.describe Datadog::Core::ProcessDiscovery do
  let(:content) do
    native_fd = described_class.instance_variable_get(:@file_descriptor)

    # Extract content from created memfd
    fd = described_class._native_to_rb_int(native_fd)
    # This MUST have autoclose set to false, or the file descriptor will be closed when the buffer is garbage collected,
    # causing an error when the tracer will be shutdown, or even closing the wrong file descriptor if it has been reused,
    # causing flaky specs and other issues.
    buffer = IO.new(fd, autoclose: false)
    buffer.rewind
    MessagePack.unpack(buffer.read)
  end

  describe ".publish" do
    context "when libdatadog API is not available" do
      it "returns nil" do
        stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", "test")
        expect(described_class.publish(nil)).to be_nil
      end
    end

    context "on macOS" do
      before do
        stub_const("RUBY_PLATFORM", "x86_64-darwin19")
        allow(Datadog.logger).to receive(:debug)
      end

      it "returns nil" do
        expect(described_class.publish(nil)).to be_nil
      end

      it "debug logs about not being available on macOS" do
        expect(Datadog.logger).to receive(:debug) { |&block| expect(block.call).to include("not yet supported on macOS") }

        described_class.publish(nil)
      end
    end

    context "when libdatadog API is available", if: !PlatformHelpers.mac? do
      before do
        Datadog.configure do |c|
          c.service = "dummy-service" # Manually set so it isn't set to fallback service name that we don't control
        end
      end

      after do
        Datadog.configuration.reset!
      end

      context "with all settings provided" do
        let(:settings) do
          instance_double(
            "Datadog::Core::Configuration::Setting",
            service: "test-service",
            env: "test-env",
            version: "1.0.0",
            experimental_propagate_process_tags_enabled: propagate_process_tags
          )
        end

        context "when process tags are enabled" do
          let(:propagate_process_tags) { true }

          it "stores metadata successfully" do
            described_class.publish(settings)

            expect(content).to include(
              "runtime_id" => Datadog::Core::Environment::Identity.id,
              "tracer_language" => Datadog::Core::Environment::Identity.lang,
              "tracer_version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
              "hostname" => Datadog::Core::Environment::Socket.hostname,
              "service_name" => "test-service",
              "service_env" => "test-env",
              "service_version" => "1.0.0",
              "process_tags" => Datadog::Core::Environment::Process.serialized
            )
          end
        end

        context "when process tags are disabled" do
          let(:propagate_process_tags) { false }

          it "does not include process_tags in metadata" do
            described_class.publish(settings)

            expect(content).to include("process_tags" => "")
          end
        end

        context "when running in a containerized environment" do
          let(:propagate_process_tags) { true }

          before do
            allow(Datadog::Core::Environment::Container).to receive(:container_id).and_return("container-id-1")
          end

          it "includes container_id in metadata" do
            described_class.publish(settings)

            expect(content).to include("container_id" => "container-id-1")
          end
        end
      end

      context "with missing optional settings" do
        let(:settings) do
          instance_double(
            "Datadog::Core::Configuration::Setting",
            service: nil,
            env: nil,
            version: nil,
            experimental_propagate_process_tags_enabled: true
          )
        end

        it "stores metadata successfully" do
          described_class.publish(settings)

          # If the string is empty, it should be replaced by None when converting C strings to Rust types.
          # Thus not appearing in the content.
          expect(content).to include(
            "runtime_id" => Datadog::Core::Environment::Identity.id,
            "tracer_language" => Datadog::Core::Environment::Identity.lang,
            "tracer_version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
            "hostname" => Datadog::Core::Environment::Socket.hostname,
            "process_tags" => Datadog::Core::Environment::Process.serialized
          )
        end
      end
    end
  end

  describe "when forked", if: !PlatformHelpers.mac? do
    reset_at_fork_monkey_patch_for_components!

    before do
      skip_if_libdatadog_not_supported

      Datadog.configure do |c|
        c.service = "test-service" # Manually set so it isn't set to fallback service name that we don't control
        c.experimental_propagate_process_tags_enabled = true
      end
    end

    after do
      Datadog.configuration.reset!
    end

    it "updates the process discovery file descriptor" do
      allow(described_class).to receive(:publish).and_call_original

      parent_runtime_id = Datadog::Core::Environment::Identity.id

      expect_in_fork do
        expect(described_class).to have_received(:publish)
        expect(content).to include(
          "runtime_id" => Datadog::Core::Environment::Identity.id,
          "tracer_language" => Datadog::Core::Environment::Identity.lang,
          "tracer_version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
          "hostname" => Datadog::Core::Environment::Socket.hostname,
          "service_name" => "test-service",
          "process_tags" => Datadog::Core::Environment::Process.serialized
        )
        expect(content.fetch("runtime_id")).to_not eq(parent_runtime_id)
      end
    end
  end

  describe "with real configuration", if: !PlatformHelpers.mac? do
    before do
      skip_if_libdatadog_not_supported

      described_class.shutdown!
    end

    after do
      Datadog.configuration.reset!
      described_class.shutdown!
    end

    context "when process tags are enabled" do
      before do
        Datadog.configure do |c|
          c.service = "test-service"
          c.experimental_propagate_process_tags_enabled = true
        end
      end

      let(:expected_tags) { Datadog::Core::Environment::Process.serialized }

      it "includes process tags" do
        described_class.publish(Datadog.configuration)

        expect(content).to include("process_tags" => expected_tags)
      end
    end

    context "when process tags are disabled" do
      it "excludes process tags" do
        Datadog.configure do |c|
          c.service = "test-service"
          c.experimental_propagate_process_tags_enabled = false
        end

        described_class.publish(Datadog.configuration)

        expect(content).to include("process_tags" => "")
      end
    end
  end

  describe "OTel process context support", if: !PlatformHelpers.mac? do
    before do
      skip_if_libdatadog_not_supported

      allow(Datadog::Core::Environment::Container).to receive(:container_id).and_return("test-container-id")

      Datadog.configure do |c|
        c.service = "otel-test-service"
        c.env = "otel-test-env"
        c.version = "1.2.3"
        c.experimental_propagate_process_tags_enabled = true
      end
    end

    after do
      Datadog.configuration.reset!
    end

    let(:process_context) { read_otel_ctx }
    let(:resource_attributes) { process_context.resource.attributes.map { |kv| [kv.key, kv.value.string_value] }.to_h }
    let(:extra_attributes) { process_context.extra_attributes.map { |kv| [kv.key, kv.value.string_value] }.to_h }

    it "publishes process context in OTel format with correct attributes" do
      described_class.publish(Datadog.configuration)

      expect(resource_attributes).to eq(
        "service.name" => "otel-test-service",
        "deployment.environment.name" => "otel-test-env",
        "service.version" => "1.2.3",
        "service.instance.id" => Datadog::Core::Environment::Identity.id,
        "telemetry.sdk.language" => "ruby",
        "telemetry.sdk.version" => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
        "telemetry.sdk.name" => "libdatadog",
        "host.name" => Datadog::Core::Environment::Socket.hostname,
        "container.id" => "test-container-id"
      )

      expect(extra_attributes).to include("datadog.process_tags" => Datadog::Core::Environment::Process.serialized)
    end

    it "preserves threadlocal metadata through enablement, disablement, and shutdown in a fresh process",
      if: PlatformHelpers.linux? && PlatformHelpers.mri? do
      stdout, stderr, status = Open3.capture3(
        {"DD_TRACE_OTEL_CTX_ENABLED" => "false"},
        RbConfig.ruby,
        "-I", File.expand_path("../../../lib", __dir__),
        "-e", <<~RUBY,
          require "datadog"

          [false, true, false, true, :shutdown].each do |enabled|
            if enabled == :shutdown
              Datadog::Core::ProcessDiscovery.shutdown!
              GC.start
            else
              Datadog.configure do |c|
                c.service = "threadlocal-lifecycle"
                c.tracing.otel_thread_context_enabled = enabled
                c.telemetry.enabled = false
                c.remote.enabled = false
                c.diagnostics.startup_logs.enabled = false
                c.logger.instance = Logger.new($stderr)
              end
            end

            mapping = File.foreach("/proc/self/maps").find do |line|
              line.include?("/memfd:OTEL_CTX") ||
                line.include?("[anon:OTEL_CTX]") ||
                line.include?("[anon_shmem:OTEL_CTX]")
            end
            raise "No OTEL_CTX mapping found" unless mapping

            File.open("/proc/self/mem", "rb") do |memory|
              memory.seek(mapping.split("-").first.to_i(16))
              signature, version, size, timestamp, address = memory.read(32).unpack("a8L<L<Q<Q<")
              raise "Invalid OTEL_CTX header" unless signature == "OTEL_CTX" && version == 2 && timestamp > 0

              memory.seek(address)
              puts [memory.read(size)].pack("m0")
            end
          end
        RUBY
      )

      expect(status.success?).to be(true), "Lifecycle subprocess failed: #{stderr}"
      snapshots = stdout.lines.map { |line| Otel::ProcessCtx::ProcessContext.decode(line.chomp.unpack1("m0")) }
      expect(snapshots.size).to eq(5)
      initial, enabled, disabled, reenabled, shutdown = snapshots

      expect(initial.extra_attributes.map(&:key)).not_to include(
        "threadlocal.schema_version",
        "threadlocal.attribute_key_map",
      )

      keys = enabled.extra_attributes.map(&:key)
      expect(keys).to include("threadlocal.schema_version").once
      expect(keys).to include("threadlocal.attribute_key_map").once
      values = enabled.extra_attributes.map { |kv| [kv.key, kv.value] }.to_h
      expect(values.fetch("threadlocal.schema_version").string_value).to eq("tlsdesc_v1_dev")
      expect(
        values.fetch("threadlocal.attribute_key_map").array_value.values.map(&:string_value)
      ).to eq(["datadog.local_root_span_id"])

      expect(disabled.extra_attributes).to match_array(enabled.extra_attributes)
      expect(reenabled.extra_attributes).to match_array(enabled.extra_attributes)
      expect(shutdown).to eq(reenabled)
    end

    context "with threadlocal metadata", if: PlatformHelpers.linux? && PlatformHelpers.mri? do
      before do
        Datadog.configure do |c|
          c.tracing.otel_thread_context_enabled = true
        end

        described_class.publish(Datadog.configuration)
      end

      shared_examples "published threadlocal metadata" do
        it "publishes the schema and key map exactly once" do
          keys = process_context.extra_attributes.map(&:key)
          expect(keys).to include("threadlocal.schema_version").once
          expect(keys).to include("threadlocal.attribute_key_map").once

          values = process_context.extra_attributes.map { |kv| [kv.key, kv.value] }.to_h
          expect(values.fetch("threadlocal.schema_version").string_value).to eq("tlsdesc_v1_dev")
          expect(
            values.fetch("threadlocal.attribute_key_map").array_value.values.map(&:string_value)
          ).to eq(["datadog.local_root_span_id"])
        end
      end

      include_examples "published threadlocal metadata"

      context "after repeated publication" do
        before do
          %w[service another-service yet-another-service].each do |service|
            Datadog.configuration.service = service
            described_class.publish(Datadog.configuration)
          end
        end

        include_examples "published threadlocal metadata"

        it "preserves updated process metadata when adding threadlocal attributes" do
          expect(resource_attributes).to include("service.name" => "yet-another-service")
        end
      end

      it "preserves metadata after fork without changing the parent" do
        parent_context = read_otel_ctx
        parent_runtime_id = Datadog::Core::Environment::Identity.id

        expect(parent_context.extra_attributes.map(&:key)).to include(
          "threadlocal.schema_version",
          "threadlocal.attribute_key_map"
        )

        expect_in_fork do
          described_class.after_fork

          child_runtime_id = Datadog::Core::Environment::Identity.id
          expect(child_runtime_id).not_to eq(parent_runtime_id)

          child_context = read_otel_ctx
          expect(child_context.extra_attributes).to match_array(parent_context.extra_attributes)

          attributes = child_context.resource.attributes.map { |kv| [kv.key, kv.value.string_value] }.to_h
          expect(attributes).to include(
            "service.instance.id" => child_runtime_id,
            "service.name" => "otel-test-service"
          )
        end

        expect(read_otel_ctx).to eq(parent_context)
      end
    end

    context "when app uses fork" do
      it "updates the process context with the new runtime_id" do
        described_class.publish(Datadog.configuration)

        parent_runtime_id = Datadog::Core::Environment::Identity.id

        expect_in_fork do
          described_class.after_fork # Simulate what Components.after_fork does

          child_runtime_id = Datadog::Core::Environment::Identity.id
          expect(child_runtime_id).not_to eq(parent_runtime_id)

          expect(resource_attributes).to include(
            "service.instance.id" => child_runtime_id,
            "service.name" => "otel-test-service",
          )
        end
      end
    end

    def read_otel_ctx
      mapping_address = find_otel_ctx_mapping
      raise "No OTel_CTX mapping found" unless mapping_address

      header = read_header(mapping_address)
      raise "Invalid OTEL_CTX" unless header[:signature] == "OTEL_CTX" && header[:version] == 2

      payload_bytes = read_memory(header[:payload_ptr], header[:payload_size])
      Otel::ProcessCtx::ProcessContext.decode(payload_bytes)
    end

    def find_otel_ctx_mapping
      File.foreach("/proc/self/maps") do |line|
        if line.include?("[anon_shmem:OTEL_CTX]") ||
            line.include?("[anon:OTEL_CTX]") ||
            line.include?("/memfd:OTEL_CTX")
          return line.split("-").first.to_i(16)
        end
      end
    end

    def read_header(address)
      header_bytes = read_memory(address, 32)
      {
        signature: header_bytes[0, 8],
        version: header_bytes[8, 4].unpack1("V"),
        payload_size: header_bytes[12, 4].unpack1("V"),
        payload_ptr: header_bytes[24, 8].unpack1("Q<"),
      }
    end

    def read_memory(address, size)
      File.open("/proc/self/mem", "rb") do |f|
        f.seek(address)
        f.read(size)
      end
    end
  end
end

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_message "otel.processctx.AnyValue" do
    optional :string_value, :string, 1
    optional :array_value, :message, 5, "otel.processctx.ArrayValue"
  end

  add_message "otel.processctx.ArrayValue" do
    repeated :values, :message, 1, "otel.processctx.AnyValue"
  end

  add_message "otel.processctx.KeyValue" do
    optional :key, :string, 1
    optional :value, :message, 2, "otel.processctx.AnyValue"
  end

  add_message "otel.processctx.Resource" do
    repeated :attributes, :message, 1, "otel.processctx.KeyValue"
  end

  add_message "otel.processctx.ProcessContext" do
    optional :resource, :message, 1, "otel.processctx.Resource"
    repeated :extra_attributes, :message, 2, "otel.processctx.KeyValue"
  end
end

module Otel
  module ProcessCtx
    AnyValue = Google::Protobuf::DescriptorPool.generated_pool.lookup("otel.processctx.AnyValue").msgclass
    ArrayValue = Google::Protobuf::DescriptorPool.generated_pool.lookup("otel.processctx.ArrayValue").msgclass
    KeyValue = Google::Protobuf::DescriptorPool.generated_pool.lookup("otel.processctx.KeyValue").msgclass
    Resource = Google::Protobuf::DescriptorPool.generated_pool.lookup("otel.processctx.Resource").msgclass
    ProcessContext = Google::Protobuf::DescriptorPool.generated_pool.lookup("otel.processctx.ProcessContext").msgclass
  end
end
