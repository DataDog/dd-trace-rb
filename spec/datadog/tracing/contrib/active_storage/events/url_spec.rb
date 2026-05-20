# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/event_helpers'
require 'datadog/tracing/contrib/active_storage/events/url'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::Url do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('service_url.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.url')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.url') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        service: 'S3',
        key: 'images/photo.jpg',
        url: 'https://s3.amazonaws.com/bucket/images/photo.jpg',
      }
    end

    include_context 'Active Storage configuration'

    it 'sets the span resource' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('S3: images/photo.jpg')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.type).to eq('http')
    end

    it 'sets service, key, and url tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to eq('S3')
      expect(span.get_tag('active_storage.key')).to eq('images/photo.jpg')
      expect(span.get_tag('active_storage.url')).to eq('https://s3.amazonaws.com/bucket/images/photo.jpg')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('url')
    end
  end
end
