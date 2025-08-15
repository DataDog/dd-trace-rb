# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/trace_keeper'

RSpec.describe Datadog::AppSec::TraceKeeper do
  describe '.keep!' do
    context 'when trace is given' do
      let(:trace) { Datadog::Tracing::TraceOperation.new }

      it 'sets trace source tag' do
        expect { described_class.keep!(trace) }
          .to change { trace.get_tag('_dd.p.ts') }.from(nil).to('02')
      end

      it 'sets trace decision maker tag' do
        expect { described_class.keep!(trace) }
          .to change { trace.get_tag('_dd.p.dm') }.from(nil).to('-5')
      end
    end

    context 'when trace is not given' do
      it { expect { described_class.keep!(nil) }.to_not raise_error }
    end
  end
end
