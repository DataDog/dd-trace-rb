# frozen_string_literal: true

begin
  require 'active_storage'
rescue LoadError
  puts 'ActiveStorage not supported in this version of Rails'
end

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/active_storage/integration'

RSpec.describe 'ActiveStorage instrumentation', execute_in_fork: Rails.version.to_i >= 8 do
  before do
    skip unless defined?(::ActiveStorage)
  end

  after { remove_patch!(:active_storage) }
  include_context 'Rails test application'

  context 'with active_storage instrumentation' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :active_storage
      end

      # Initialize the application
      app
    end

    describe 'service operations' do
      let(:service) { ActiveStorage::Blob.service }
      let(:key) { 'test_key_123' }
      let(:data) { 'test content' }

      after do
        # Clean up any test files
        service.delete(key) if service.exist?(key)
      rescue StandardError
        # Ignore cleanup errors
        nil
      end

      it 'instruments upload operations' do
        service.upload(key, StringIO.new(data))

        span = spans.find { |s| s.name == 'active_storage.upload' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.span_type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments download operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        service.download(key)

        span = spans.find { |s| s.name == 'active_storage.download' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.span_type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments exist operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        result = service.exist?(key)

        expect(result).to be true
        span = spans.find { |s| s.name == 'active_storage.exist' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.span_type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.exist')).to eq(true)
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments delete operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        service.delete(key)

        span = spans.find { |s| s.name == 'active_storage.delete' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.span_type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments url operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        service.url(key, expires_in: 5.minutes)

        span = spans.find { |s| s.name == 'active_storage.url' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.span_type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
        expect(span.get_tag('active_storage.url')).not_to be_nil
      end

      context 'with download_chunk' do
        it 'instruments download_chunk operations' do
          service.upload(key, StringIO.new(data))
          clear_traces!

          service.download_chunk(key, 0..5)

          span = spans.find { |s| s.name == 'active_storage.download_chunk' }
          expect(span).not_to be_nil
          expect(span.resource).to match(/#{key}/)
          expect(span.span_type).to eq('http')
          expect(span.get_tag('active_storage.key')).to eq(key)
          expect(span.get_tag('active_storage.service')).not_to be_nil
          expect(span.get_tag('active_storage.range')).to eq(0..5)
        end
      end

      context 'with custom configuration' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :active_storage, service_name: 'my-storage-service'
          end
        end

        it 'uses the custom service name' do
          service.upload(key, StringIO.new(data))

          span = spans.find { |s| s.name == 'active_storage.upload' }
          expect(span).not_to be_nil
          expect(span.service).to eq('my-storage-service')
        end
      end

      context 'with analytics enabled' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :active_storage, analytics_enabled: true, analytics_sample_rate: 0.5
          end
        end

        it 'sets analytics tags on spans' do
          service.upload(key, StringIO.new(data))

          span = spans.find { |s| s.name == 'active_storage.upload' }
          expect(span).not_to be_nil
          expect(span.get_metric('_dd1.sr.eausr')).to eq(0.5)
        end
      end
    end

    describe 'blob operations' do
      let(:blob) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('test content'),
          filename: 'test.txt',
          content_type: 'text/plain'
        )
      end

      after do
        blob.purge if blob.persisted?
      rescue StandardError
        nil
      end

      it 'instruments blob upload through create_and_upload!' do
        # The blob creation already happened in the let block
        # Check for upload span
        span = spans.find { |s| s.name == 'active_storage.upload' }
        expect(span).not_to be_nil
        expect(span.get_tag('active_storage.key')).not_to be_nil
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments blob download' do
        blob # Create the blob
        clear_traces!

        blob.download

        span = spans.find { |s| s.name == 'active_storage.download' }
        expect(span).not_to be_nil
        expect(span.get_tag('active_storage.key')).to eq(blob.key)
      end

      it 'instruments blob deletion' do
        key = blob.key
        clear_traces!

        blob.purge

        span = spans.find { |s| s.name == 'active_storage.delete' }
        expect(span).not_to be_nil
        expect(span.get_tag('active_storage.key')).to eq(key)
      end
    end

    describe 'integration disable' do
      before do
        Datadog.configure do |c|
          c.tracing.instrument :active_storage, enabled: false
        end
      end

      it 'does not create spans when disabled' do
        service = ActiveStorage::Blob.service
        key = 'test_disabled_key'

        service.upload(key, StringIO.new('test'))
        service.delete(key)

        active_storage_spans = spans.select { |s| s.name.start_with?('active_storage') }
        expect(active_storage_spans).to be_empty
      end
    end
  end
end
