require 'spec_helper'
require 'datadog/tracing/contrib/redis/tags'

require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::Redis::Tags do
  let(:client) { double('client') }
  let(:span) { Datadog::Tracing::SpanOperation.new('fake') }
  let(:raw_command) { 'SET key value' }

  describe '.set_common_tags' do
    context 'when an error occurs' do
      it 'logs the error' do
        allow(client).to receive(:host).and_raise(StandardError.new('Oops...'))
        expect(Datadog.logger).to receive(:error).with('Oops...')
        expect(Datadog::Core::Telemetry::Logger).to receive(:report).with(a_kind_of(StandardError))

        expect do
          described_class.set_common_tags(client, span, raw_command)
        end.not_to raise_error
      end
    end
  end
end
