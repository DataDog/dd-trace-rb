require 'spec_helper'

require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::V1::Dependency do
  subject(:dependency) { described_class.new(name: name, version: version, hash: hash) }

  let(:hash) { nil }
  let(:name) { 'mongodb' }
  let(:version) { nil }

  it { is_expected.to have_attributes(name: name, hash: hash, version: version) }

  describe '#initialize' do
    context ':name' do
      it_behaves_like 'a required string parameter', 'name'
    end

    context ':version' do
      let(:version) { '2.2.5' }

      it_behaves_like 'an optional string parameter', 'version'

      context 'and :hash' do
        let(:hash) { 'test-hash' }

        it 'report argument conflict' do
          expect { dependency }.to raise_error(ArgumentError)
        end
      end
    end

    context ':hash' do
      it_behaves_like 'an optional string parameter', 'hash'
    end
  end

  describe '#to_h' do
    subject(:to_h) { dependency.to_h }

    let(:hash) { nil }
    let(:name) { 'mongodb' }
    let(:version) { '2.2.5' }

    it do
      is_expected.to eq(
        name: name,
        version: version
      )
    end
  end
end
