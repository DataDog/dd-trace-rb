# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/active_storage/events/delete_prefixed'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::DeletePrefixed do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('service_delete_prefixed.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.delete_prefixed')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.delete_prefixed') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        service: 'S3',
        prefix: 'tmp/uploads/'
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

    it 'sets the span resource' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('S3: tmp/uploads/')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.span_type).to eq('http')
    end

    it 'sets service and prefix tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to eq('S3')
      expect(span.get_tag('active_storage.prefix')).to eq('tmp/uploads/')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('delete_prefixed')
    end
  end
end
