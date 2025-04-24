# frozen_string_literal: true

require 'msgpack'

require 'spec_helper'
require 'datadog/core/process_discovery'

# TODO: Re-enable this once we have updated libdatadog to 17.1
RSpec.xdescribe Datadog::Core::ProcessDiscovery do
  describe '.get_and_store_metadata' do
    context 'when libdatadog API is not available' do
      it 'returns nil' do
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', 'test')
        expect(described_class.get_and_store_metadata(nil, Datadog::Core::Logger.new(StringIO.new))).to be_nil
      end
    end

    context 'when libdatadog API is available' do
      context 'with all settings provided' do
        let(:settings) do
          instance_double(
            'Datadog::Core::Configuration::Setting',
            service: 'test-service',
            env: 'test-env',
            version: '1.0.0'
          )
        end

        it 'stores metadata successfully' do
          native_fd = described_class.get_and_store_metadata(settings, Datadog::Core::Logger.new(StringIO.new))

          # Extract content from created memfd
          fd = described_class._native_to_rb_int(native_fd)
          buffer = IO.new(fd)
          buffer.rewind
          raw_content = buffer.read
          content = MessagePack.unpack(raw_content)

          expect(content).to eq(
            {
              'schema_version' => 1,
              'runtime_id' => Datadog::Core::Environment::Identity.id,
              'tracer_language' => Datadog::Core::Environment::Identity.lang,
              'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
              'hostname' => Datadog::Core::Environment::Socket.hostname,
              'service_name' => 'test-service',
              'service_env' => 'test-env',
              'service_version' => '1.0.0'
            }
          )
        end
      end

      context 'with missing optional settings' do
        let(:settings) do
          instance_double(
            'Datadog::Core::Configuration::Setting',
            service: nil,
            env: nil,
            version: nil
          )
        end

        it 'stores metadata successfully' do
          native_fd = described_class.get_and_store_metadata(settings, Datadog::Core::Logger.new(StringIO.new))

          # Extract content from created memfd
          fd = described_class._native_to_rb_int(native_fd)
          buffer = IO.new(fd)
          buffer.rewind
          raw_content = buffer.read
          content = MessagePack.unpack(raw_content)

          # If the string is empty, it should be replaced by None when converting C strings to Rust types.
          # Thus not appearing in the content.
          expect(content).to eq(
            {
              'schema_version' => 1,
              'runtime_id' => Datadog::Core::Environment::Identity.id,
              'tracer_language' => Datadog::Core::Environment::Identity.lang,
              'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
              'hostname' => Datadog::Core::Environment::Socket.hostname
            }
          )
        end
      end
    end
  end
end
