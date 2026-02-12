# frozen_string_literal: true

require 'msgpack'

require 'spec_helper'
require 'datadog/core/process_discovery'

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

  describe '.publish' do
    context 'when libdatadog API is not available' do
      it 'returns nil' do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'test')
        expect(described_class.publish(nil)).to be_nil
      end
    end

    context 'when libdatadog API is available' do
      before do
        Datadog.configure do |c|
          c.service = 'dummy-service' # Manually set so it isn't set to fallback service name that we don't control
        end
      end

      after do
        Datadog.configuration.reset!
      end

      context 'with all settings provided' do
        let(:settings) do
          instance_double(
            'Datadog::Core::Configuration::Setting',
            service: 'test-service',
            env: 'test-env',
            version: '1.0.0',
            experimental_propagate_process_tags_enabled: propagate_process_tags
          )
        end

        context 'when process tags are enabled' do
          let(:propagate_process_tags) { true }

          it 'stores metadata successfully' do
            described_class.publish(settings)

            expect(content).to include(
              'runtime_id' => Datadog::Core::Environment::Identity.id,
              'tracer_language' => Datadog::Core::Environment::Identity.lang,
              'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
              'hostname' => Datadog::Core::Environment::Socket.hostname,
              'service_name' => 'test-service',
              'service_env' => 'test-env',
              'service_version' => '1.0.0',
              'process_tags' => Datadog::Core::Environment::Process.serialized
            )
          end
        end

        context 'when process tags are disabled' do
          let(:propagate_process_tags) { false }

          it 'does not include process_tags in metadata' do
            described_class.publish(settings)

            expect(content).to include('process_tags' => '')
          end
        end

        context 'when running in a containerized environment' do
          let(:propagate_process_tags) { true }

          before do
            allow(Datadog::Core::Environment::Container).to receive(:container_id).and_return('container-id-1')
          end

          it 'includes container_id in metadata' do
            described_class.publish(settings)

            expect(content).to include('container_id' => 'container-id-1')
          end
        end
      end

      context 'with missing optional settings' do
        let(:settings) do
          instance_double(
            'Datadog::Core::Configuration::Setting',
            service: nil,
            env: nil,
            version: nil,
            experimental_propagate_process_tags_enabled: true
          )
        end

        it 'stores metadata successfully' do
          described_class.publish(settings)

          # If the string is empty, it should be replaced by None when converting C strings to Rust types.
          # Thus not appearing in the content.
          expect(content).to include(
            'runtime_id' => Datadog::Core::Environment::Identity.id,
            'tracer_language' => Datadog::Core::Environment::Identity.lang,
            'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
            'hostname' => Datadog::Core::Environment::Socket.hostname,
            'process_tags' => Datadog::Core::Environment::Process.serialized
          )
        end
      end
    end
  end

  describe 'when forked', skip: !LibdatadogHelpers.supported? do
    reset_at_fork_monkey_patch_for_components!

    before do
      Datadog.configure do |c|
        c.service = 'test-service' # Manually set so it isn't set to fallback service name that we don't control
        c.experimental_propagate_process_tags_enabled = true
      end
    end

    after do
      Datadog.configuration.reset!
    end

    it 'updates the process discovery file descriptor' do
      allow(described_class).to receive(:publish).and_call_original

      parent_runtime_id = Datadog::Core::Environment::Identity.id

      expect_in_fork do
        expect(described_class).to have_received(:publish)
        expect(content).to include(
          'runtime_id' => Datadog::Core::Environment::Identity.id,
          'tracer_language' => Datadog::Core::Environment::Identity.lang,
          'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
          'hostname' => Datadog::Core::Environment::Socket.hostname,
          'service_name' => 'test-service',
          'process_tags' => Datadog::Core::Environment::Process.serialized
        )
        expect(content.fetch('runtime_id')).to_not eq(parent_runtime_id)
      end
    end
  end

  describe 'with real configuration', skip: !LibdatadogHelpers.supported? do
    before do
      described_class.shutdown!
    end

    after do
      Datadog.configuration.reset!
      described_class.shutdown!
    end

    context 'when process tags are enabled' do
      it 'includes process tags' do
        Datadog.configure do |c|
          c.service = 'test-service'
          c.experimental_propagate_process_tags_enabled = true
        end

        expected_tags = Datadog::Core::Environment::Process.serialized

        described_class.publish(Datadog.configuration)

        expect(content).to include('process_tags' => expected_tags)
        expect(expected_tags).not_to be_empty
      end
    end

    context 'when process tags are disabled' do
      it 'excludes process tags' do
        Datadog.configure do |c|
          c.service = 'test-service'
          c.experimental_propagate_process_tags_enabled = false
        end

        described_class.publish(Datadog.configuration)

        expect(content).to include('process_tags' => '')
      end
    end
  end
end
