require "datadog/di/spec_helper"
require "datadog/di/transport"

RSpec.describe Datadog::DI::Transport do
  di_test

  let(:agent_settings) do
    instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings)
  end

  describe '.new' do
    it 'creates an instance using agent settings' do
      expect(agent_settings).to receive(:hostname).and_return('localhost')
      expect(agent_settings).to receive(:port).and_return(8126)
      expect(agent_settings).to receive(:timeout_seconds).and_return(1)
      expect(agent_settings).to receive(:ssl).and_return(false)

      expect(described_class.new(agent_settings)).to be_a(described_class)
    end
  end

  # These are fairly basic tests. The agent will accept all kinds of
  # semantically nonsensical payloads. The tests here are useful to
  # ascertain that things like content type is set correctly for each
  # endpoint.
  #
  # Realistically, the only test that can check that the payload being
  # sent is the correct one is a system test.
  describe 'send methods' do
    before(:all) do
      # These tests require a functional datadog agent running at the
      # configured (via agent_host & agent_port) location.
      # CI has "dd-apm-test-agent" running which does not implement
      # debugger endpoints, and thus is not suitable for these tests.
      # These tests can be run locally, and test coverage in CI is
      # accomplished via system tests.
      unless agent_host && agent_port && ENV['TEST_DATADOG_AGENT'] == '1'
        skip "Set TEST_DATADOG_AGENT=1, DD_AGENT_HOST and DD_TRACE_AGENT_PORT in environment to run these tests"
      end
    end

    let(:port) { agent_port }

    before do
      expect(agent_settings).to receive(:hostname).and_return(agent_host)
      expect(agent_settings).to receive(:port).and_return(port)
      expect(agent_settings).to receive(:timeout_seconds).and_return(1)
      expect(agent_settings).to receive(:ssl).and_return(false)
    end

    let(:client) do
      described_class.new(agent_settings)
    end

    describe '.send_diagnostics' do
      let(:payload) do
        {}
      end

      it 'does not raise exceptions' do
        expect do
          client.send_diagnostics(payload)
        end.not_to raise_exception
      end
    end

    describe '.send_input' do
      context 'empty payload' do
        let(:payload) do
          {}
        end

        it 'does not raise exceptions' do
          expect do
            client.send_input(payload)
          end.not_to raise_exception
        end
      end

      context 'partial DI payload' do
        let(:payload) do
          {
            service: 'rspec',
            "debugger.snapshot": {
              id: '1234',
            },
          }
        end

        it 'does not raise exceptions' do
          expect do
            client.send_input(payload)
          end.not_to raise_exception
        end
      end
    end

    context 'when agent is not listening' do
      # Use a bogus port
      let(:port) { 99999 }

      describe '.send_diagnostics' do
        let(:payload) do
          {}
        end

        it 'raises AgentCommunicationError' do
          expect do
            client.send_diagnostics(payload)
          end.to raise_exception(Datadog::DI::Error::AgentCommunicationError, /(?:Connection refused|connect).*99999/)
        end
      end

      describe '.send_input' do
        let(:payload) do
          {}
        end

        it 'raises AgentCommunicationError' do
          expect do
            client.send_input(payload)
          end.to raise_exception(Datadog::DI::Error::AgentCommunicationError, /(?:Connection refused|connect).*99999/)
        end
      end
    end
  end
end
