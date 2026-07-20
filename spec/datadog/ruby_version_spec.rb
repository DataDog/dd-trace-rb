require 'spec_helper'

require 'datadog/ruby_version'

RSpec.describe Datadog::RubyVersion do
  describe '.is' do
    subject(:is) { described_class.is?(*requirements, ruby_version: Gem::Version.new(ruby_version)) }

    context 'with a single requirement' do
      let(:requirements) { ['< 4'] }

      context 'when the version matches' do
        let(:ruby_version) { '3.0.5' }

        it { is_expected.to be true }
      end

      context 'when the version does not match' do
        let(:ruby_version) { '4.1.0' }

        it { is_expected.to be false }
      end
    end

    context 'with multiple requirements' do
      let(:requirements) { ['>= 3.2', '< 3.2.3'] }

      context 'when all requirements are satisfied' do
        let(:ruby_version) { '3.2.2' }

        it { is_expected.to be true }
      end

      context 'when only some requirements are satisfied' do
        let(:ruby_version) { '3.3.0' }

        it { is_expected.to be false }
      end
    end

    # These cases are the whole reason this helper exists: a naive lexical comparison such as
    # `RUBY_VERSION < "3.2.3"` is wrongly `true` for "3.2.10" and "3.2.11" because they sort before
    # "3.2.3" as plain strings.
    context 'with versions that would break a lexical string comparison' do
      let(:requirements) { ['< 3.2.3'] }

      context 'on 3.2.10' do
        let(:ruby_version) { '3.2.10' }

        it { is_expected.to be false }
      end
    end
  end
end
