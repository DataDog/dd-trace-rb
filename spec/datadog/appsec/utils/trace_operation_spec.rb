require 'datadog/appsec/spec_helper'
require 'datadog/appsec/utils/trace_operation'

RSpec.describe Datadog::AppSec::Utils::TraceOperation do
  describe '#appsec_standalone_reject?' do
    subject(:appsec_standalone_reject?) do
      described_class.appsec_standalone_reject?(trace_op)
    end

    let(:trace_op) { Datadog::Tracing::TraceOperation.new(**options) }
    let(:options) { {} }
    let(:appsec_standalone) { false }
    let(:distributed_appsec_event) { '0' }

    before do
      allow(Datadog.configuration.appsec.standalone).to receive(:enabled).and_return(appsec_standalone)
      trace_op.set_tag(Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT, distributed_appsec_event) if trace_op
    end

    it { is_expected.to be false }

    context 'when AppSec standalone is enabled' do
      let(:appsec_standalone) { true }

      it { is_expected.to be true }

      context 'without a trace' do
        let(:trace_op) { nil }

        it { is_expected.to be true }
      end

      context 'with a distributed AppSec event' do
        let(:distributed_appsec_event) { '1' }

        it { is_expected.to be false }
      end
    end
  end
end
