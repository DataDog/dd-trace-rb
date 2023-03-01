require 'datadog/tracing/contrib/support/spec_helper'

require 'dalli'
require 'ddtrace'
require 'datadog/tracing/contrib/dalli/quantize'

RSpec.describe Datadog::Tracing::Contrib::Dalli::Quantize do
  describe '#format_command' do
    subject(:formatted_command) { described_class.format_command(op, args) }

    context 'output' do
      let(:op) { :set }
      let(:args) { [123, 'foo', nil] }

      it { is_expected.to eq('set 123 foo') }
    end

    context 'truncation' do
      let(:op) { :set }
      let(:args) { ['foo', 'A' * 100] }

      it { expect(formatted_command.size).to eq(Datadog::Tracing::Contrib::Dalli::Ext::QUANTIZE_MAX_CMD_LENGTH) }
      it { is_expected.to end_with('...') }
      it { is_expected.to eq("set foo #{'A' * 89}...") }
    end

    context 'different encodings' do
      let(:op) { :set }
      let(:args) { ["\xa1".force_encoding('iso-8859-1'), "\xa1\xa1".force_encoding('euc-jp')] }

      it { is_expected.to match(/BLOB \(OMITTED\)/) }
    end
  end
end
