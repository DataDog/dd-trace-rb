require 'spec_helper'

require 'datadog/core/utils/url'

RSpec.describe Datadog::Core::Utils::Url do
  describe '.filter_basic_auth' do
    subject(:filtered_url) { described_class.filter_basic_auth(url) }

    context 'with https' do
      context 'with username and password' do
        let(:url) { 'https://gitlab-ci-token:AAA_bbb@gitlab.com/DataDog/systems-test.git' }

        it { is_expected.to eq('https://gitlab.com/DataDog/systems-test.git') }
      end

      context 'with username' do
        let(:url) { 'https://token@gitlab.com/user/project.git' }

        it { is_expected.to eq('https://gitlab.com/user/project.git') }
      end

      context 'without credentials' do
        let(:url) { 'https://gitlab.com/DataDog/systems-test.git' }

        it { is_expected.to eq('https://gitlab.com/DataDog/systems-test.git') }
      end
    end

    context 'with ssh' do
      context 'with username and password' do
        let(:url) { 'ssh://gitlab-ci-token:AAA_bbb@gitlab.com/DataDog/systems-test.git' }

        it { is_expected.to eq('ssh://gitlab.com/DataDog/systems-test.git') }
      end

      context 'with username' do
        let(:url) { 'ssh://token@gitlab.com/user/project.git' }

        it { is_expected.to eq('ssh://gitlab.com/user/project.git') }
      end

      context 'without credentials' do
        let(:url) { 'ssh://gitlab.com/DataDog/systems-test.git' }

        it { is_expected.to eq('ssh://gitlab.com/DataDog/systems-test.git') }
      end
    end

    context 'without protocol' do
      context 'without credentials' do
        let(:url) { 'gitlab.com/DataDog/systems-test.git' }

        it { is_expected.to eq('gitlab.com/DataDog/systems-test.git') }
      end

      context 'with credentials' do
        let(:url) { 'git@github.com:user/project.git' }

        it { is_expected.to eq('git@github.com:user/project.git') }
      end
    end

    context 'with nil' do
      let(:url) { nil }

      it { is_expected.to be_nil }
    end
  end
end
