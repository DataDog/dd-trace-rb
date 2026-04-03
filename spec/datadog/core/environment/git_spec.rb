require 'spec_helper'

require 'datadog/core/environment/git'

RSpec.describe Datadog::Core::Environment::Git do
  subject(:settings) { Datadog.configuration }

  describe '.git_repository_url' do
    context "when #{Datadog::Core::Git::Ext::ENV_REPOSITORY_URL} is set" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Git::Ext::ENV_REPOSITORY_URL => 'https://gitlab-ci-token:AAA_bbb@gitlab.com/DataDog/systems-test.git') do
          example.run
        end
      end

      it 'returns the URL with basic auth filtered out' do
        expect(described_class.git_repository_url(settings)).to eq('https://gitlab.com/DataDog/systems-test.git')
      end
    end

    context "when #{Datadog::Core::Git::Ext::ENV_REPOSITORY_URL} is not set" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Git::Ext::ENV_REPOSITORY_URL => nil) do
          example.run
        end
      end

      it 'returns nil' do
        expect(described_class.git_repository_url(settings)).to be nil
      end
    end

    context 'when set programmatically via Datadog.configure' do
      before do
        Datadog.configure { |c| c.git.repository_url = 'https://programmatic.example.com/repo.git' }
      end

      it 'returns the programmatically configured value' do
        expect(described_class.git_repository_url(settings)).to eq('https://programmatic.example.com/repo.git')
      end
    end
  end
end
