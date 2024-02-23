require 'spec_helper'

require 'datadog/core/environment/git'

RSpec.describe Datadog::Core::Environment::Git do
  def remove_cached_variables
    if described_class.instance_variable_defined?(:@git_repository_url)
      described_class.remove_instance_variable(:@git_repository_url)
    end

    if described_class.instance_variable_defined?(:@git_commit_sha)
      described_class.remove_instance_variable(:@git_commit_sha)
    end
  end

  around do |example|
    ClimateControl.modify(env_key => env_value) do
      example.run
    end
  end

  before do
    remove_cached_variables
  end

  after do
    remove_cached_variables
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
