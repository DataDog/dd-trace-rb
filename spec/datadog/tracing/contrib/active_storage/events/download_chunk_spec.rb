# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/contrib/active_storage/events/download_chunk'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::DownloadChunk do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('service_download_chunk.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.download_chunk')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.download_chunk') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        service: 'S3',
        key: 'videos/large_file.mp4',
        range: 'bytes=0-1023',
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
      expect(span.resource).to eq('S3: videos/large_file.mp4')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.type).to eq('http')
    end

    it 'sets service, key, and range tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to eq('S3')
      expect(span.get_tag('active_storage.key')).to eq('videos/large_file.mp4')
      expect(span.get_tag('active_storage.range')).to eq('bytes=0-1023')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('download_chunk')
    end
  end
end
