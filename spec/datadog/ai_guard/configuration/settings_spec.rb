# frozen_string_literal: true

require 'spec_helper'
require 'datadog/ai_guard/configuration'

RSpec.describe Datadog::AIGuard::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'ai_guard' do
    describe '#enabled' do
      context 'when DD_AI_GUARD_ENABLED is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_ENABLED' => nil) { example.run }
        end

        it { expect(settings.ai_guard.enabled).to be(true) }
      end

      context 'when DD_AI_GUARD_ENABLED is defined as true' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_ENABLED' => 'true') { example.run }
        end

        it { expect(settings.ai_guard.enabled).to be(true) }
      end

      context 'when DD_AI_GUARD_ENABLED is defined as false' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_ENABLED' => 'false') { example.run }
        end

        it { expect(settings.ai_guard.enabled).to be(false) }
      end
    end

    describe '#enabled=' do
      context 'when set to true' do
        before { settings.ai_guard.enabled = true }

        it { expect(settings.ai_guard.enabled).to be(true) }
      end

      context 'when set to false' do
        before { settings.ai_guard.enabled = false }

        it { expect(settings.ai_guard.enabled).to be(false) }
      end
    end

    describe '#endpoint' do
      context 'when DD_AI_GUARD_ENDPOINT is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_ENDPOINT' => nil) { example.run }
        end

        it { expect(settings.ai_guard.endpoint).to eq('https://app.datadoghq.com/api/v2/ai-guard') }
      end

      context 'when DD_AI_GUARD_ENDPOINT is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_ENDPOINT' => 'https://app.datad0g.com/api/v2/ai-guard') do
            example.run
          end
        end

        it { expect(settings.ai_guard.endpoint).to eq('https://app.datad0g.com/api/v2/ai-guard') }
      end
    end

    describe '#endpoint=' do
      it 'changes endpoint value' do
        expect { settings.ai_guard.endpoint = 'https://app.datadoghq.com/path/to/ai-guard' }
          .to change { settings.ai_guard.endpoint }.to('https://app.datadoghq.com/path/to/ai-guard')
      end
    end

    describe '#api_key' do
      context 'when DD_AI_GUARD_API_KEY is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_API_KEY' => nil) { example.run }
        end

        it { expect(settings.ai_guard.api_key).to be_nil }
      end

      context 'when DD_AI_GUARD_API_KEY is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_API_KEY' => 'some-api-key') do
            example.run
          end
        end

        it { expect(settings.ai_guard.api_key).to eq('some-api-key') }
      end
    end

    describe '#api_key=' do
      it 'changes API key value' do
        expect { settings.ai_guard.api_key = 'another-api-key' }
          .to change { settings.ai_guard.api_key }.to('another-api-key')
      end
    end

    describe '#application_key' do
      context 'when DD_AI_GUARD_APPLICATION_KEY is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_APPLICATION_KEY' => nil) { example.run }
        end

        it { expect(settings.ai_guard.application_key).to be_nil }
      end

      context 'when DD_AI_GUARD_APPLICATION_KEY is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_APPLICATION_KEY' => 'some-application-key') do
            example.run
          end
        end

        it { expect(settings.ai_guard.application_key).to eq('some-application-key') }
      end
    end

    describe '#application_key=' do
      it 'changes application key value' do
        expect { settings.ai_guard.application_key = 'another-application-key' }
          .to change { settings.ai_guard.application_key }.to('another-application-key')
      end
    end

    describe '#timeout' do
      context 'when DD_AI_GUARD_TIMEOUT is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_TIMEOUT' => nil) { example.run }
        end

        it { expect(settings.ai_guard.timeout).to eq(10_000) }
      end

      context 'when DD_AI_GUARD_TIMEOUT is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_TIMEOUT' => '20000') { example.run }
        end

        it { expect(settings.ai_guard.timeout).to eq(20_000) }
      end
    end

    describe '#timeout=' do
      it 'changes timeout value' do
        expect { settings.ai_guard.timeout = 30_000 }
          .to change { settings.ai_guard.timeout }.to(30_000)
      end
    end

    describe '#max_content_size_bytes' do
      context 'when DD_AI_GUARD_MAX_CONTENT_SIZE is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_MAX_CONTENT_SIZE' => nil) { example.run }
        end

        it { expect(settings.ai_guard.max_content_size_bytes).to eq(512 * 1024) }
      end

      context 'when DD_AI_GUARD_MAX_CONTENT_SIZE is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_MAX_CONTENT_SIZE' => '262144') { example.run }
        end

        it { expect(settings.ai_guard.max_content_size_bytes).to eq(262_144) }
      end
    end

    describe '#max_content_size_bytes=' do
      it 'changes max_content_size_bytes value' do
        expect { settings.ai_guard.max_content_size_bytes = 1024 * 1024 }
          .to change { settings.ai_guard.max_content_size_bytes }.to(1024 * 1024)
      end
    end

    describe '#max_messages_length' do
      context 'when DD_AI_GUARD_MAX_MESSAGES_LENGTH is not defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_MAX_MESSAGES_LENGTH' => nil) { example.run }
        end

        it { expect(settings.ai_guard.max_messages_length).to eq(16) }
      end

      context 'when DD_AI_GUARD_MAX_MESSAGES_LENGTH is defined' do
        around do |example|
          ClimateControl.modify('DD_AI_GUARD_MAX_MESSAGES_LENGTH' => '32') { example.run }
        end

        it { expect(settings.ai_guard.max_messages_length).to eq(32) }
      end
    end

    describe '#max_messages_length=' do
      it 'changes max_messages_length value' do
        expect { settings.ai_guard.max_messages_length = 24 }
          .to change { settings.ai_guard.max_messages_length }.to(24)
      end
    end
  end
end
