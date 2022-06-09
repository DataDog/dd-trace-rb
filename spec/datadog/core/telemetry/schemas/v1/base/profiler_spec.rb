require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/profiler'
require 'datadog/core/telemetry/schemas/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Profiler do
  subject(:profiler) { described_class.new(version: version) }

  let(:version) { '1.0' }

  it { is_expected.to have_attributes(version: version) }

  describe '#initialize' do
    context 'when :version' do
      it_behaves_like 'a string argument', 'version'
    end
  end
end
