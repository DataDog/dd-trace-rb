# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/event_helpers'
require 'datadog/tracing/contrib/active_storage/events/update_metadata'
require 'datadog/tracing/span_operation'

RSpec.describe Datadog::Tracing::Contrib::ActiveStorage::Events::UpdateMetadata do
  describe '.event_name' do
    it 'returns the correct event name' do
      expect(described_class.event_name).to eq('service_update_metadata.active_storage')
    end
  end

  describe '.span_name' do
    it 'returns the correct span name' do
      expect(described_class.span_name).to eq('active_storage.update_metadata')
    end
  end

  describe '.process' do
    let(:span) { Datadog::Tracing::SpanOperation.new('active_storage.update_metadata') }
    let(:event) { double('event') }
    let(:id) { double('id') }
    let(:payload) do
      {
        service: 'S3',
        key: 'documents/report.pdf',
        content_type: 'application/pdf',
        disposition: 'attachment',
      }
    end

    include_context 'Active Storage configuration'

    it 'sets the span resource' do
      described_class.process(span, event, id, payload)
      expect(span.resource).to eq('S3: documents/report.pdf')
    end

    it 'sets the span type' do
      described_class.process(span, event, id, payload)
      expect(span.type).to eq('http')
    end

    it 'sets service, key, content_type, and disposition tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('active_storage.service')).to eq('S3')
      expect(span.get_tag('active_storage.key')).to eq('documents/report.pdf')
      expect(span.get_tag('active_storage.content_type')).to eq('application/pdf')
      expect(span.get_tag('active_storage.disposition')).to eq('attachment')
    end

    it 'sets component and operation tags' do
      described_class.process(span, event, id, payload)
      expect(span.get_tag('component')).to eq('active_storage')
      expect(span.get_tag('operation')).to eq('update_metadata')
    end
  end
end
