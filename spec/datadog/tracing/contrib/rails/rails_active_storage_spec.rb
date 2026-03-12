# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/active_storage/integration'

RSpec.describe 'ActiveStorage instrumentation', execute_in_fork: Rails.version.to_i >= 8, skip: Gem.loaded_specs['activestorage'].nil? do
  after do
    remove_patch!(:active_storage)
    Datadog.configuration.tracing[:active_storage].reset_options!
  end

  include_context 'Rails test application'

  context 'with active_storage instrumentation' do
    let(:active_storage_root) { Dir.mktmpdir('dd-trace-rb-active-storage') }
    let(:active_storage_service_configurations) do
      {
        test: {
          service: 'Disk',
          root: active_storage_root,
        },
      }
    end

    # Defined in support/base.rb
    let(:initialize_block) do
      super_block = super()
      app_root = active_storage_root

      proc do
        instance_exec(&super_block)
        config.active_storage.service = :test
        config.root = app_root
        # The Rails test harness re-initializes the app for each example.
        # On Rails 6.0 and 6.1, keeping classes cached and disabling change-based
        # reloads avoids the boot-time Active Storage autoload/reload conflict.
        if Rails.version.to_i == 6
          config.cache_classes = true
          config.reload_classes_only_on_change = false if config.respond_to?(:reload_classes_only_on_change=)
        end
      end
    end

    before do
      write_active_storage_config_file

      Datadog.configure do |c|
        c.tracing.instrument :active_storage
      end

      app
      ensure_active_storage_service!
    end

    after do
      FileUtils.remove_entry_secure(active_storage_root)
    end

    def write_active_storage_config_file
      active_storage_config_path = File.join(active_storage_root, 'config', 'storage.yml')
      FileUtils.mkdir_p(File.dirname(active_storage_config_path))
      File.write(
        active_storage_config_path,
        YAML.dump(
          'test' => {
            'service' => 'Disk',
            'root' => active_storage_root,
          }
        )
      )
    end

    def ensure_active_storage_service!
      service = ActiveStorage::Service.configure(:test, active_storage_service_configurations)

      if ActiveStorage::Blob.respond_to?(:services=) && defined?(ActiveStorage::Service::Registry)
        ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(active_storage_service_configurations)
      end

      ActiveStorage::Blob.service = service
    end

    describe 'service operations' do
      let(:service) { ActiveStorage::Blob.service }
      let(:key) { 'test_key_123' }
      let(:data) { 'test content' }
      let(:url_options) do
        {
          expires_in: 5.minutes,
          filename: ActiveStorage::Filename.new('test.txt'),
          content_type: 'text/plain',
          disposition: :inline,
        }
      end

      def set_active_storage_url_context(protocol:, host:)
        current = ActiveStorage.const_get(:Current)
        return if current.nil?

        if current.respond_to?(:url_options=)
          current.url_options = {protocol: protocol, host: host}
        elsif current.respond_to?(:host=)
          current.host = "#{protocol}://#{host}"
        end
      end

      def clear_active_storage_url_context
        current = ActiveStorage.const_get(:Current)
        return if current.nil?

        if current.respond_to?(:url_options=)
          current.url_options = nil
        elsif current.respond_to?(:host=)
          current.host = nil
        end
      end

      after do
        # Clean up any test files
        service.delete(key) if service.exist?(key)
      rescue
        # Ignore cleanup errors
        nil
      end

      it 'instruments upload operations' do
        service.upload(key, StringIO.new(data))

        span = spans.find { |s| s.name == 'active_storage.upload' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.type).to eq('http')
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
        expect(span.type).to eq('http')
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
        expect(span.type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.exist')).to eq('true')
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments delete operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        service.delete(key)

        span = spans.find { |s| s.name == 'active_storage.delete' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments url operations' do
        service.upload(key, StringIO.new(data))
        clear_traces!

        set_active_storage_url_context(protocol: 'http', host: 'example.com')
        service.url(key, **url_options)

        span = spans.find { |s| s.name == 'active_storage.url' }
        expect(span).not_to be_nil
        expect(span.resource).to match(/#{key}/)
        expect(span.type).to eq('http')
        expect(span.get_tag('active_storage.key')).to eq(key)
        expect(span.get_tag('active_storage.service')).not_to be_nil
        expect(span.get_tag('active_storage.url')).not_to be_nil
      ensure
        clear_active_storage_url_context
      end

      context 'with download_chunk' do
        it 'instruments download_chunk operations' do
          service.upload(key, StringIO.new(data))
          clear_traces!

          service.download_chunk(key, 0..5)

          span = spans.find { |s| s.name == 'active_storage.download_chunk' }
          expect(span).not_to be_nil
          expect(span.resource).to match(/#{key}/)
          expect(span.type).to eq('http')
          expect(span.get_tag('active_storage.key')).to eq(key)
          expect(span.get_tag('active_storage.service')).not_to be_nil
          expect(span.get_tag('active_storage.range')).to eq('0..5')
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
      def create_blob
        if ActiveStorage::Blob.respond_to?(:create_and_upload!)
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new('test content'),
            filename: 'test.txt',
            content_type: 'text/plain'
          )
        else
          ActiveStorage::Blob.create_after_upload!(
            io: StringIO.new('test content'),
            filename: 'test.txt',
            content_type: 'text/plain'
          )
        end
      end

      before do
        @blob = create_blob
      end

      after do
        @blob&.purge
        @blob = nil
      end

      it 'instruments blob upload during blob creation' do
        # Check for upload span
        upload_span = spans.find { |s| s.name == 'active_storage.upload' }
        expect(upload_span).not_to be_nil
        expect(upload_span.get_tag('active_storage.key')).not_to be_nil
        expect(upload_span.get_tag('active_storage.service')).not_to be_nil
      end

      it 'instruments blob download' do
        clear_traces!

        @blob.download

        download_span = spans.find { |s| s.name == 'active_storage.download' }
        expect(download_span).not_to be_nil
        expect(download_span.get_tag('active_storage.key')).to eq(@blob.key)
      end

      it 'instruments blob deletion' do
        key = @blob.key
        clear_traces!

        @blob.purge

        delete_span = spans.find { |s| s.name == 'active_storage.delete' }
        expect(delete_span).not_to be_nil
        expect(delete_span.get_tag('active_storage.key')).to eq(key)
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
