require 'spec_helper'

require 'datadog/core/telemetry/schemas/base/v1/host'

RSpec.describe Datadog::Core::Telemetry::Schemas::Base::V1::Host do
  describe '#initialize' do
    context 'given no parameters' do
      subject(:host) { described_class.new }
      it { is_expected.to be_a_kind_of(described_class) }
    end

    context 'given all parameters' do
      subject(:host) do
        described_class.new(container_id, hostname, kernel_name, kernel_release, kernel_version, os, os_version)
      end
      let(:container_id) { 'd39b145254d1f9c337fdd2be132f6650c6f5bc274bfa28aaa204a908a1134096' }
      let(:hostname) { 'i-09ecf74c319c49be8' }
      let(:kernel_name) { 'Linux' }
      let(:kernel_release) { '5.4.0-1037-gcp' }
      let(:kernel_version) { '#40~18.04.1-Ubuntu SMP Fri Feb 5 15:41:35 UTC 2021' }
      let(:os) { 'GNU/Linux' }
      let(:os_version) { 'ubuntu 18.04.5 LTS (Bionic Beaver)' }
      it {
        is_expected
          .to have_attributes(container_id: container_id, hostname: hostname, os: os, os_version: os_version,
                              kernel_release: kernel_release, kernel_version: kernel_version, kernel_name: kernel_name)
      }
    end
  end
end
