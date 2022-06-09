require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/dependency'
require 'datadog/core/telemetry/schemas/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Dependency do
  subject(:dependency) { described_class.new(name: name, version: version, hash: hash) }

  let(:hash) { '3e2e2c2362c89aa01bc0e004681e' }
  let(:name) { 'mongodb' }
  let(:version) { '2.2.5' }

  it { is_expected.to have_attributes(name: name, hash: hash, version: version) }

  describe '#initialize' do
    context 'when :name' do
      it_behaves_like 'a string argument', 'name'
    end

    context 'when :version' do
      it_behaves_like 'an optional string argument', 'version'
    end

    context 'when :hash' do
      it_behaves_like 'an optional string argument', 'hash'
    end
  end
end
