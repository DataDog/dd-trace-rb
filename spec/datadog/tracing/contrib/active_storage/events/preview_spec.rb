# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/active_storage/events/preview'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::Preview do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('preview.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.preview')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.preview') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        key: 'variants/abc123/preview.jpg'
      }
    end

    before do
      allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(
        double(
          service_name: nil,
          analytics_enabled: false,
          analytics_sample_rate: 1.0
        )
      )
    end

    it 'sets the span resource to the key' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('variants/abc123/preview.jpg')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.span_type).to eq('http')
    end

    it 'sets the key tag' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.key')).to eq('variants/abc123/preview.jpg')
    end

    it 'does not set the service tag' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to be_nil
    end
  end
end
