# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Component do
  forking_platform_only

  before(:all) do
    # We need to ensure the patch is present.
    # There is a unit test for the patcher itself which clears the callbacks,
    # we need to reinstall our callback if the callback got installed before
    # that test is run and this test is run afterwards.
    Datadog::Core::Configuration::Components.const_get(:AT_FORK_ONLY_ONCE).send(:reset_ran_once_state_for_tests)

    # Clear out existing handlers so that our handler is registered exactly once.
    Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.remote.poll_interval_seconds = 60 # Long interval to avoid unnecessary syncs
      # Host may be overridden by environment variables
      settings.agent.host = 'localhost'
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

  context 'when remote config is disabled' do
    before do
      settings.remote.enabled = false
    end

    it 'stays disabled in child process' do
      expect(component).to be_nil

      expect_in_fork do
        expect(components.remote).to be_nil
      end
    end
  end

  context 'when remote config is enabled' do
    before do
      # after_fork handler goes through the global variable.
      #
      # Cannot use +expect+ here because the call is in child process.
      allow(Datadog).to receive(:components).and_return(components)
    end

    it 'is enabled in child process' do
      expect(component).to be_a(Datadog::Core::Remote::Component)
      expect(component.client).to be_a(Datadog::Core::Remote::Client)

      expect_in_fork do
        expect(components.remote).to be_a(Datadog::Core::Remote::Component)
        expect(components.remote.client).to be_a(Datadog::Core::Remote::Client)
      end
    end

    context 'when remote config is started' do
      before do
        component.start
      end

      it 'recreates client with new ID after fork' do
        parent_client_id = component.client.id
        parent_client_object_id = component.client.object_id

        expect(component.started?).to be true
        expect(parent_client_id).to be_a(String)
        expect(parent_client_id).to match(/^[0-9a-f-]+$/)

        expect_in_fork do
          child_component = components.remote

          # Remote config should still be started
          expect(child_component.started?).to be true

          # Client should be a new instance
          expect(child_component.client.object_id).not_to eq(parent_client_object_id)

          # Client ID should be different
          child_client_id = child_component.client.id
          expect(child_client_id).to be_a(String)
          expect(child_client_id).to match(/^[0-9a-f-]+$/)
          expect(child_client_id).not_to eq(parent_client_id)
        end
      end

      it 'resets healthy flag after fork' do
        # Make the component healthy in the parent
        component.instance_variable_set(:@healthy, true)
        expect(component.healthy).to be true

        expect_in_fork do
          child_component = components.remote

          # Healthy flag should be reset to false
          expect(child_component.healthy).to be false
        end
      end

      it 'preserves configuration after fork' do
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
end
