# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/active_storage/events/delete'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::Delete do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('service_delete.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.delete')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.delete') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        service: 'GCS',
        key: 'images/photo.jpg',
      }
    end

    before do
      config = double('config')
      allow(config).to receive(:[]).with(:service_name).and_return(nil)
      allow(config).to receive(:[]).with(:analytics_enabled).and_return(false)
      allow(config).to receive(:[]).with(:analytics_sample_rate).and_return(1.0)
      allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(config)
    end

    it 'sets the span resource' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('GCS: images/photo.jpg')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.type).to eq('http')
    end

    it 'sets service and key tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to eq('GCS')
      expect(span.get_tag('active_storage.key')).to eq('images/photo.jpg')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('delete')
    end
  end
end
