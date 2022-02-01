# typed: false
require 'spec_helper'

require 'datadog/tracing'
require 'datadog/opentelemetry/span'

RSpec.describe Datadog::OpenTelemetry::Span do
  context 'when implemented in Datadog::Span' do
    before { expect(Datadog::Tracing::SpanOperation <= described_class).to be true }

    subject(:span) { Datadog::Tracing::SpanOperation.new(name) }

    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
    let(:name) { 'opentelemetry.span' }

    describe '#set_tag' do
      subject(:set_tag) { span.set_tag(tag_name, tag_value) }

      context "when given '#{Datadog::OpenTelemetry::Span::TAG_SERVICE_NAME}'" do
        let(:tag_name) { Datadog::OpenTelemetry::Span::TAG_SERVICE_NAME }
        let(:tag_value) { 'opentelemetry-service' }

        before { set_tag }

        it { expect(span.get_tag(tag_name)).to eq tag_value }
        it { expect(span.service).to eq tag_value }
      end

      context "when given '#{Datadog::OpenTelemetry::Span::TAG_SERVICE_VERSION}'" do
        let(:tag_name) { Datadog::OpenTelemetry::Span::TAG_SERVICE_VERSION }
        let(:tag_value) { '1.2.3' }

        before { set_tag }

        it { expect(span.get_tag(tag_name)).to eq tag_value }
        it { expect(span.get_tag(Datadog::Core::Environment::Ext::TAG_VERSION)).to eq tag_value }
      end

      context 'when given an arbitrary tag' do
        let(:tag_name) { 'custom-tag' }
        let(:tag_value) { 'custom-value' }

        before { set_tag }

        it { expect(span.get_tag(tag_name)).to eq tag_value }
      end
    end
  end
end
