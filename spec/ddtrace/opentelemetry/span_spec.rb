require 'spec_helper'

require 'ddtrace'
require 'ddtrace/opentelemetry/span'

RSpec.describe Datadog::OpenTelemetry::Span do
  context 'when implemented in Datadog::Span' do
    before { expect(Datadog::Span <= described_class).to be true }

    subject(:span) { Datadog::Span.new(tracer, name) }
    let(:tracer) { instance_double(Datadog::Tracer) }
    let(:name) { 'opentelemetry.span' }

    describe '#set_tag' do
      subject(:set_tag) { span.set_tag(tag_name, tag_value) }

      context "when given '#{Datadog::OpenTelemetry::Span::TAG_SERVICE_VERSION}'" do
        let(:tag_name) { Datadog::OpenTelemetry::Span::TAG_SERVICE_VERSION }
        let(:tag_value) { '1.2.3' }

        before { set_tag }

        it { expect(span.get_tag(tag_name)).to eq tag_value }
        it { expect(span.get_tag(Datadog::Ext::Environment::TAG_VERSION)).to eq tag_value }
      end
    end
  end
end
