# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/crashtracking/agent_base_url'

RSpec.describe Datadog::Core::Crashtracking::AgentBaseUrl do
  describe '.resolve' do
    context 'when using HTTP adapter' do
      context 'when SSL is enabled' do
        let(:agent_settings) do
          double(
            'agent_settings',
            adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
            ssl: true,
            hostname: 'example.com',
            port: 8080
          )
        end

        it 'returns the correct base URL' do
          expect(described_class.resolve(agent_settings)).to eq('https://example.com:8080/')
        end
      end

      context 'when SSL is disabled' do
        let(:agent_settings) do
          double(
            'agent_settings',
            adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
            ssl: false,
            hostname: 'example.com',
            port: 8080
          )
        end

        it 'returns the correct base URL' do
          expect(described_class.resolve(agent_settings)).to eq('http://example.com:8080/')
        end
      end
    end

    context 'when using UnixSocket adapter' do
      let(:agent_settings) do
        double(
          'agent_settings',
          adapter: Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER,
          uds_path: '/var/run/datadog.sock'
        )
      end

      it 'returns the correct base URL' do
        expect(described_class.resolve(agent_settings)).to eq('unix:///var/run/datadog.sock')
      end
    end

    context 'when using unknownm adapter' do
      let(:agent_settings) { double('agent_settings', adapter: 'unknown') }

      it 'returns nil' do
        expect(described_class.resolve(agent_settings)).to be_nil
      end
    end
  end
end
