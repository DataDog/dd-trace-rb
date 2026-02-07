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
      config = double('config')
      allow(config).to receive(:[]).with(:service_name).and_return(nil)
      allow(config).to receive(:[]).with(:analytics_enabled).and_return(false)
      allow(config).to receive(:[]).with(:analytics_sample_rate).and_return(1.0)
      allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(config)
    end

    it 'sets the span resource to the key' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('variants/abc123/preview.jpg')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.type).to eq('http')
    end

    it 'sets the key tag' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.key')).to eq('variants/abc123/preview.jpg')
    end

    it 'does not set the service tag' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to be_nil
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('preview')
    end
  end
end
