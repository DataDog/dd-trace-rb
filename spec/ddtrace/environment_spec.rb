require 'spec_helper'

require 'ddtrace'
require 'ddtrace/environment'

RSpec.describe Datadog::Environment do
  describe '::env' do
    subject(:env) { described_class.env }
    context "when #{Datadog::Ext::Environment::ENV_ENVIRONMENT}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_ENVIRONMENT => environment) do
          example.run
        end
      end

      context 'is not defined' do
        let(:environment) { nil }
        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:environment) { 'env-value' }
        it { is_expected.to eq(environment) }
      end
    end
  end

  describe '::tags' do
    subject(:tags) { described_class.tags }

    context "when #{Datadog::Ext::Environment::ENV_TAGS}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_TAGS => env_tags) do
          example.run
        end
      end

      context 'is not defined' do
        let(:env_tags) { nil }
        it { is_expected.to eq({}) }
      end

      context 'is defined' do
        let(:env_tags) { 'a:1,b:2' }

        it { is_expected.to include('a' => '1', 'b' => '2') }

        context 'with an invalid tag' do
          context do
            let(:env_tags) { '' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { 'a' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { ':' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { ',' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { 'a:' }
            it { is_expected.to eq({}) }
          end
        end

        context 'and when ::env' do
          context 'is set' do
            before { allow(described_class).to receive(:env).and_return(nil) }
            it { is_expected.to_not include('env') }
          end

          context 'is not set' do
            let(:env_value) { 'env-value' }
            before { allow(described_class).to receive(:env).and_return(env_value) }
            it { is_expected.to include('env' => env_value) }
          end
        end
      end

      context 'conflicts with ::env' do
        let(:env_tags) { "env:#{tag_env_value}" }
        let(:tag_env_value) { 'tag-env-value' }
        let(:env_value) { 'env-value' }

        before { allow(described_class).to receive(:env).and_return(env_value) }

        it { is_expected.to include('env' => env_value) }
      end
    end
  end
end
