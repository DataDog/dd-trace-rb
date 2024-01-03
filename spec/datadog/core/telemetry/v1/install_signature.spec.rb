require 'spec_helper'

require 'datadog/core/telemetry/v1/product'

RSpec.describe Datadog::Core::Telemetry::V1::InstallSignature do
  subject(:install_signature) do
    described_class.new(install_id: install_id, install_type: install_type, install_time: install_time)
  end

  let(:install_id) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }
  let(:install_type) { 'k8s_single_step' }
  let(:install_time) { '1703188212' }

  it { is_expected.to have_attributes(install_id: install_id, install_type: install_type, install_time: install_time) }

  describe '#initialize' do
    context 'when :install_id' do
      context 'is nil' do
        let(:install_id) { nil }
        it { is_expected.to have_attributes(install_id: nil, install_type: install_type, install_time: install_time) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid' do
        let(:install_id) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :install_type' do
      context 'is nil' do
        let(:install_type) { nil }
        it { is_expected.to have_attributes(install_id: install_id, install_type: nil, install_time: install_time) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid' do
        let(:install_type) { 'k8s_single_step' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end

    context 'when :install_time' do
      context 'is nil' do
        let(:install_time) { nil }
        it { is_expected.to have_attributes(install_id: install_id, install_type: install_type, install_time: nil) }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid' do
        let(:install_time) { '1703188212' }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end

  describe '#to_h' do
    subject(:to_h) { install_signature.to_h }

    let(:install_id) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }
    let(:install_type) { 'k8s_single_step' }
    let(:install_time) { '1703188212' }

    it do
      is_expected.to eq(
        install_id: install_id,
        install_type: install_type,
        install_time: install_time
      )
    end
  end
end
