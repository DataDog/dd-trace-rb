require 'spec_helper'

require 'datadog/tracing/contrib/utils/database'

RSpec.describe Datadog::Tracing::Contrib::Utils::Database do
  describe '#normalize_vendor' do
    subject(:result) { described_class.normalize_vendor(value) }

    context 'when given' do
      context 'nil' do
        let(:value) { nil }

        it { is_expected.to eq('defaultdb') }
      end

      context 'sqlite3' do
        let(:value) { 'sqlite3' }

        it { is_expected.to eq('sqlite') }
      end

      context 'mysql2' do
        let(:value) { 'mysql2' }

        it { is_expected.to eq('mysql2') }
      end

      context 'postgresql' do
        let(:value) { 'postgresql' }

        it { is_expected.to eq('postgres') }
      end

      context 'customdb' do
        let(:value) { 'customdb' }

        it { is_expected.to eq(value) }
      end
    end
  end
end
