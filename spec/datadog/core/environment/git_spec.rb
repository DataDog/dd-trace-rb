require 'spec_helper'

require 'datadog/core/environment/git'

RSpec.describe Datadog::Core::Environment::Git do
  around do |example|
    ClimateControl.modify(env_key => env_value) do
      example.run
    end
  end

  describe '.git_repository_url' do
    subject { described_class.git_repository_url }

    let(:env_key) { Datadog::Core::Git::Ext::ENV_REPOSITORY_URL }
    let(:env_value) { 'https://gitlab-ci-token:AAA_bbb@gitlab.com/DataDog/systems-test.git' }

    it { is_expected.to eq('https://gitlab.com/DataDog/systems-test.git') }
  end

  describe '.git_commit_sha' do
    subject { described_class.git_commit_sha }

    let(:env_key) { Datadog::Core::Git::Ext::ENV_COMMIT_SHA }
    let(:env_value) { '1234567890abcdef' }

    it { is_expected.to eq('1234567890abcdef') }
  end
end
