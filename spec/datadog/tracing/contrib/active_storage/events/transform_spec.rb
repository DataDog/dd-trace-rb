# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/active_storage/events/transform'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::Transform do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('transform.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.transform')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.transform') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) { {} }

    before do
      config = double('config')
      allow(config).to receive(:[]).with(:service_name).and_return(nil)
      allow(config).to receive(:[]).with(:analytics_enabled).and_return(false)
      allow(config).to receive(:[]).with(:analytics_sample_rate).and_return(1.0)
      allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(config)
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.span_type).to eq('http')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('transform')
    end

    context 'when service_name is configured' do
      before do
        config = double('config')
        allow(config).to receive(:[]).with(:service_name).and_return('custom_storage')
        allow(config).to receive(:[]).with(:analytics_enabled).and_return(false)
        allow(config).to receive(:[]).with(:analytics_sample_rate).and_return(1.0)
        allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(config)
      end

      it 'sets the custom service name' do
        described_class.process(span, event, id, payload)
        expect(span.service).to eq('custom_storage')
      end
    end
  end
end
