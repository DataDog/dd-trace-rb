require 'spec_helper'
require 'datadog/core/environment/identity'

RSpec.describe Datadog::Core::Environment::Identity do
  describe '::id' do
    subject(:id) { described_class.id }

    it { is_expected.to be_a_kind_of(String) }

    context 'when invoked twice' do
      it { expect(described_class.id).to eq(described_class.id) }
    end

    context 'when invoked around a fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      let(:before_fork_id) { described_class.id }
      let(:inside_fork_id) { described_class.id }
      let(:after_fork_id) { described_class.id }

      it do
        # Check before forking
        expect(before_fork_id).to be_a_kind_of(String)

        # Invoke in fork, make sure expectations run before continuing.
        expect_in_fork do
          expect(inside_fork_id).to be_a_kind_of(String)
          expect(inside_fork_id).to_not eq(before_fork_id)
        end

        # Check after forking
        expect(after_fork_id).to eq(before_fork_id)
      end
    end
  end

  describe '::root_runtime_id' do
    subject(:root_runtime_id) { described_class.root_runtime_id }

    context 'in root process' do
      it { is_expected.to be_nil }
    end

    context 'when invoked in a fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it 'equals the parent id' do
        parent_id = described_class.id

        expect_in_fork do
          described_class.id # Triggers after_fork! update
          expect(described_class.root_runtime_id).to eq(parent_id)
        end
      end
    end
  end

  describe '::parent_runtime_id' do
    subject(:parent_runtime_id) { described_class.parent_runtime_id }

    context 'in root process' do
      it { is_expected.to be_nil }
    end

    context 'when invoked in a fork' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      it 'equals the parent id' do
        parent_id = described_class.id

        expect_in_fork do
          described_class.id # Triggers after_fork! update
          expect(described_class.parent_runtime_id).to eq(parent_id)
        end
      end
    end
  end

  describe '::lang' do
    subject(:lang) { described_class.lang }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::LANG) }
  end

  describe '::lang_engine' do
    subject(:lang_engine) { described_class.lang_engine }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::LANG_ENGINE) }
  end

  describe '::lang_interpreter' do
    subject(:lang_interpreter) { described_class.lang_interpreter }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::LANG_INTERPRETER) }
  end

  describe '::lang_platform' do
    subject(:lang_platform) { described_class.lang_platform }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::LANG_PLATFORM) }
  end

  describe '::lang_version' do
    subject(:lang_version) { described_class.lang_version }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::LANG_VERSION) }
  end

  describe '::gem_datadog_version' do
    subject(:gem_datadog_version) { described_class.gem_datadog_version }

    it { is_expected.to eq(Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION) }
  end

  describe '::gem_datadog_version_semver2' do
    subject(:gem_datadog_version) { described_class.gem_datadog_version_semver2 }

    context 'when not prerelease' do
      before do
        expect(described_class).to receive(:gem_datadog_version).and_return('10.20.30'.freeze)
      end

      it { is_expected.to eq('10.20.30') }
    end

    context 'when prerelease' do
      before do
        expect(described_class).to receive(:gem_datadog_version).and_return('10.20.30.beta40'.freeze)
      end

      it { is_expected.to eq('10.20.30-beta40') }
    end

    context 'when development' do
      before do
        expect(described_class).to receive(:gem_datadog_version)
          .and_return('10.20.30.b3fe268.gha12345.ga1b2c3d4'.freeze)
      end

      it { is_expected.to eq('10.20.30+b3fe268.gha12345.ga1b2c3d4') }
    end

    context 'when prerelease and development' do
      before do
        expect(described_class).to receive(:gem_datadog_version)
          .and_return('10.20.30.beta40.b3fe268.gha12345.ga1b2c3d4'.freeze)
      end

      it { is_expected.to eq('10.20.30-beta40+b3fe268.gha12345.ga1b2c3d4') }
    end
  end
end
