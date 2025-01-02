# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/crashtracking/agent_base_url'

RSpec.describe Datadog::Core::Crashtracking::AgentBaseUrl do
  describe '.resolve' do
    context 'when using HTTP adapter' do
      context 'when SSL is enabled' do
        let(:agent_settings) do
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
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
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
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

      context 'when hostname is an IPv4 address' do
        let(:agent_settings) do
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
            ssl: false,
            hostname: '1.2.3.4',
            port: 8080
          )
        end

        it 'returns the correct base URL' do
          expect(described_class.resolve(agent_settings)).to eq('http://1.2.3.4:8080/')
        end
      end

      context 'when hostname is an IPv6 address' do
        let(:agent_settings) do
          Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
            adapter: Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER,
            ssl: false,
            hostname: '1234:1234::1',
            port: 8080
          )
        end

        it 'returns the correct base URL' do
          expect(described_class.resolve(agent_settings)).to eq('http://[1234:1234::1]:8080/')
        end
      end
    end

    context 'when using UnixSocket adapter' do
      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER,
          uds_path: '/var/run/datadog.sock'
        )
      end

      it 'returns the correct base URL' do
        expect(described_class.resolve(agent_settings)).to eq('unix:///var/run/datadog.sock')
      end
    end
  end
end
