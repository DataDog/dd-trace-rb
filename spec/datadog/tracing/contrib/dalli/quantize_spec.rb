require 'datadog/tracing/contrib/support/spec_helper'

require 'dalli'
require 'ddtrace'
require 'datadog/tracing/contrib/dalli/quantize'

RSpec.describe Datadog::Tracing::Contrib::Dalli::Quantize do
  describe '#format_command' do
    subject(:formatted_command) { described_class.format_command(op, args) }
    let(:op) { :set }

    context 'output' do
      context 'given `nil` as last element' do
        let(:args) { [123, 'foo', nil] }

        it { is_expected.to eq('set 123 foo') }
      end

      context 'given `nil` within an array' do
        let(:op) { :set }
        let(:args) { [123, nil, 'foo'] }

        it { is_expected.to eq('set 123 foo') }
      end

      context 'given a large binary as key' do
        let(:bytes) { Random.bytes(100) }
        let(:args) { [bytes, 'foo'] }

        it {
          is_expected.to eq('set 123 foo')
        }
      end
    end

    context 'truncation' do
      let(:args) { ['foo', 'A' * 100, 'B' * 100] }

      it { expect(formatted_command.size).to eq(Datadog::Tracing::Contrib::Dalli::Ext::QUANTIZE_MAX_CMD_LENGTH) }
      it { is_expected.to eq("set foo #{'A' * 89}...") }
    end

    context 'different encodings' do
      let(:args) { ["\xa1".force_encoding('iso-8859-1'), "\xa1\xa1".force_encoding('euc-jp')] }

      it { is_expected.to match(/BLOB \(OMITTED\)/) }
    end
  end
end
