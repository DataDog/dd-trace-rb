require 'spec_helper'

require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::V1::Host do
  subject(:host) do
    described_class.new(
      container_id: container_id,
      hostname: hostname,
      kernel_name: kernel_name,
      kernel_release: kernel_release,
      kernel_version: kernel_version,
      os_version: os_version,
      os: os
    )
  end

  let(:container_id) { 'd39b145254d1f9c337fdd2be132f6' }
  let(:hostname) { 'i-09ecf74c319c49be8' }
  let(:kernel_name) { 'Linux' }
  let(:kernel_release) { '5.4.0-1037-gcp' }
  let(:kernel_version) { '#40~18.04.1-Ubuntu SMP Fri Feb 5 15:41:35 UTC 2021' }
  let(:os_version) { 'ubuntu 18.04.5 LTS (Bionic Beaver)' }
  let(:os) { 'GNU/Linux' }

  it do
    is_expected.to have_attributes(
      container_id: container_id,
      hostname: hostname,
      kernel_name: kernel_name,
      kernel_release: kernel_release,
      kernel_version: kernel_version,
      os_version: os_version,
      os: os
    )
  end

  describe '#initialize' do
    context ':container_id' do
      it_behaves_like 'an optional string parameter', 'container_id'
    end

    context ':hostname' do
      it_behaves_like 'an optional string parameter', 'hostname'
    end

    context ':kernel_name' do
      it_behaves_like 'an optional string parameter', 'kernel_name'
    end

    context ':kernel_release' do
      it_behaves_like 'an optional string parameter', 'kernel_release'
    end

    context ':kernel_version' do
      it_behaves_like 'an optional string parameter', 'kernel_version'
    end

    context ':os_version' do
      it_behaves_like 'an optional string parameter', 'os_version'
    end

    context ':os' do
      it_behaves_like 'an optional string parameter', 'os'
    end

    context 'when all parameters' do
      context 'are nil' do
        let(:container_id) { nil }
        let(:hostname) { nil }
        let(:kernel_name) { nil }
        let(:kernel_release) { nil }
        let(:kernel_version) { nil }
        let(:os_version) { nil }
        let(:os) { nil }
        it { expect { host }.to raise_error(ArgumentError) }
      end
    end
  end
end
