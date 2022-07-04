require 'spec_helper'

require 'datadog/core/telemetry/v1/profiler'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::V1::Profiler do
  subject(:profiler) { described_class.new(version: version) }

  let(:version) { '1.0' }

  it { is_expected.to have_attributes(version: version) }

  describe '#initialize' do
    context ':version' do
      it_behaves_like 'a required string parameter', 'version'
    end
  end

  describe '#to_h' do
    subject(:to_h) { profiler.to_h }
    let(:version) { '1.0' }
    it do
      is_expected.to eq(
        {
          version: version
        }
      )
    end
  end
end
