require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/dependency'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Dependency do
  describe '#initialize' do
    let(:hash) { 'abb6b7ee58bf4d44d6f41c57db' }
    let(:name) { 'express' }
    let(:version) { '4.17.0' }

    context 'given only required parameters' do
      subject(:dependency) { described_class.new(name: name, version: version) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, version: version, hash: nil) }
    end

    context 'given all parameters' do
      subject(:dependency) { described_class.new(name: name, version: version, hash: hash) }
      it { is_expected.to have_attributes(hash: hash, name: name, version: version) }
    end
  end
end
