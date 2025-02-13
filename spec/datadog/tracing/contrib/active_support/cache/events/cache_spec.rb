require 'spec_helper'
require 'datadog/tracing/contrib/active_support/cache/events/cache'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Cache::Events::Cache do
  describe '.on_start' do
    context 'when an error occurs' do
      let(:span) { Datadog::Tracing::SpanOperation.new('fake') }

      it 'logs the error' do
        expect(Datadog.logger).to receive(:error).with(/key not found/)
        expect(Datadog::Core::Telemetry::Logger).to receive(:report).with(a_kind_of(StandardError))

        expect do
          described_class.on_start(span, double, double, {})
        end.not_to raise_error
      end
    end
  end
end
