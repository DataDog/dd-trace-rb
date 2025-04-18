# frozen_string_literal: true

require 'msgpack'

require 'spec_helper'
require 'datadog/core/process_discovery'

RSpec.describe Datadog::Core::ProcessDiscovery do
  describe '.get_and_store_metadata', skip: !LibdatadogHelpers.supported? do
    context 'when libdatadog API is available' do
      let(:settings) do
        instance_double(
          'Datadog::Core::Configuration::Setting',
          service: 'test-service',
          env: 'TEST_ENV=true',
          version: '1.0.0'
        )
      end

      it 'stores metadata successfully' do
        native_fd = described_class.get_and_store_metadata(settings, Datadog::Core::Logger.new($stdout))

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
            'service_env' => 'TEST_ENV=true',
            'service_version' => '1.0.0'
          }
        )
      end
    end
  end

  describe '.get_metadata' do
    context 'with all settings provided' do
      let(:settings) do
        instance_double(
          'Datadog::Core::Configuration::Setting',
          service: 'test-service',
          env: 'TEST_ENV=true',
          version: '1.0.0'
        )
      end

      it 'returns complete metadata' do
        expect(described_class.get_metadata(settings)).to eq(
          {
            schema_version: 1,
            runtime_id: Datadog::Core::Environment::Identity.id,
            tracer_language: Datadog::Core::Environment::Identity.lang,
            tracer_version: Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
            hostname: Datadog::Core::Environment::Socket.hostname,
            service_name: 'test-service',
            service_env: 'TEST_ENV=true',
            service_version: '1.0.0'
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

      it 'returns metadata with empty strings for missing values' do
        expect(described_class.get_metadata(settings)).to eq(
          {
            schema_version: 1,
            runtime_id: Datadog::Core::Environment::Identity.id,
            tracer_language: Datadog::Core::Environment::Identity.lang,
            tracer_version: Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
            hostname: Datadog::Core::Environment::Socket.hostname,
            service_name: '',
            service_env: '',
            service_version: ''
          }
        )
      end
    end
  end
end
