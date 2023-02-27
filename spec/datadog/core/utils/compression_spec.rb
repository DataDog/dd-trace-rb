require 'securerandom'
require 'datadog/core/utils/compression'

RSpec.describe Datadog::Core::Utils::Compression do
  describe '::gzip' do
    subject(:gzip) { described_class.gzip(unzipped) }

    let(:unzipped) { SecureRandom.uuid }

    it { is_expected.to be_a_kind_of(String) }

    context 'when result is unzipped' do
      subject(:gunzip) { described_class.gunzip(gzip) }

      it { is_expected.to eq(unzipped) }
    end
  end

  describe '::gunzip' do
    subject(:gunzip) { described_class.gunzip(zipped) }

    context 'given a zipped string' do
      let(:zipped) { described_class.gzip(unzipped) }
      let(:unzipped) { SecureRandom.uuid }

      it { is_expected.to eq(unzipped) }
    end
  end
end
