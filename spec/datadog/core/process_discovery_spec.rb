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
      context 'with all settings provided' do
        before do
          Datadog.configure do |c|
            c.service = 'test-service' # Manually set so it isn't set to fallback service name that we don't control
          end
        end

        let(:settings) do
          instance_double(
            'Datadog::Core::Configuration::Setting',
            service: 'test-service',
            env: 'test-env',
            version: '1.0.0'
          )
        end

        it 'stores metadata successfully' do
          described_class.publish(settings)

          expect(content).to include(
            {
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
          described_class.publish(settings)

          # If the string is empty, it should be replaced by None when converting C strings to Rust types.
          # Thus not appearing in the content.
          expect(content).to include(
            {
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

  describe 'when forked', skip: !LibdatadogHelpers.supported? do
    before do
      # Unit tests for at fork monkey patch module reset its state,
      # including the defined handlers.
      # We need to make sure that our handler is added to the list,
      # because normally it would be added during library initialization
      # and if the fork monkey patch test runs before this test,
      # the handler would get cleared out.
      Datadog::Core::Configuration::Components.const_get(:AT_FORK_ONLY_ONCE).send(:reset_ran_once_state_for_tests)

      # We also need to clear out the handlers because we could have
      # our own handler registered from the library initialization time,
      # if the at fork monkey patch did not run before this test.
      # In this case the handler would be executed twice which is
      # 1) probably not good and 2) would fail our assertions.
      Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear

      Datadog.configure do |c|
        c.service = 'test-service' # Manually set so it isn't set to fallback service name that we don't control
      end
    end

    it 'updates the process discovery file descriptor' do
      allow(described_class).to receive(:publish).and_call_original

      parent_runtime_id = Datadog::Core::Environment::Identity.id

      expect_in_fork do
        expect(described_class).to have_received(:publish)
        expect(content).to include(
          {
            'runtime_id' => Datadog::Core::Environment::Identity.id,
            'tracer_language' => Datadog::Core::Environment::Identity.lang,
            'tracer_version' => Datadog::Core::Environment::Identity.gem_datadog_version_semver2,
            'hostname' => Datadog::Core::Environment::Socket.hostname,
            'service_name' => 'test-service'
          }
        )
        expect(content.fetch('runtime_id')).to_not eq(parent_runtime_id)
      end
    end
  end
end
