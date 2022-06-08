require 'spec_helper'

require 'datadog/core/telemetry/schemas/base/v1/dependency'

RSpec.describe Datadog::Core::Telemetry::Schemas::Base::V1::Dependency do
  describe '#initialize' do
    let(:name) { 'express' }
    let(:version) { '4.17.0' }
    let(:hash) { 'abb6b7ee58bf4d44d6f41c57db' }

    context 'given only required parameters' do
      subject(:dependency) { described_class.new(name, version) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, version: version, hash: nil) }
    end

    context 'given all parameters' do
      subject(:dependency) { described_class.new(name, version, hash) }
      it {
        is_expected.to have_attributes(name: name, version: version, hash: hash)
      }
    end
  end
end
