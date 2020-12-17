require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/rails/rails_helper'
require 'ddtrace'
require 'sidekiq/testing'

require 'active_storage/engine'
require 'active_storage/attached'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'mysql2'
  require 'sqlite3'
end

RSpec.describe 'ActiveStorage instrumentation' do
  include Rack::Test::Methods
  include_context 'Rails test application'

  Sidekiq.configure_client do |config|
    config.redis = { url: ENV['REDIS_URL'] }
  end

  Sidekiq.configure_server do |config|
    config.redis = { url: ENV['REDIS_URL'] }
  end

  Sidekiq::Testing.inline!

  let(:mysql) do
    {
      database: ENV.fetch('TEST_MYSQL_DB', 'mysql'),
      host: ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'),
      password: ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root'),
      port: ENV.fetch('TEST_MYSQL_PORT', '3306')
    }
  end

  def mysql_connection_string
    "mysql2://root:#{mysql[:password]}@#{mysql[:host]}:#{mysql[:port]}/#{mysql[:database]}"
  end

  let(:application_record) do
    stub_const('ApplicationRecord', Class.new(ActiveRecord::Base) do
      self.abstract_class = true
    end)

    class Article < ApplicationRecord
      include ActiveStorage::Attached::Model
      include ActiveStorage::Reflection::ActiveRecordExtensions
      ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
      has_one_attached :image
    end

    # This is needed to ensure tests write to disk and not make http requests
    Rails.configuration.active_storage.service_configurations = {
      local: {
        service: 'Disk',
        root: '/dev/null'
      }
    }

    ActiveRecord::Base.establish_connection(mysql_connection_string)

    begin
      Article.count
    rescue ActiveRecord::StatementInvalid
      ActiveRecord::Schema.define(version: 20180101000000) do
        create_table 'articles', force: :cascade do |t|
          t.string   'title'
          t.datetime 'created_at', null: false
          t.datetime 'updated_at', null: false
        end

        create_table :active_storage_blobs do |t|
          t.string   :key,        null: false
          t.string   :filename,   null: false
          t.string   :content_type
          t.text     :metadata
          t.bigint   :byte_size,  null: false
          t.string   :checksum,   null: false
          t.datetime :created_at, null: false

          t.index [:key], unique: true
        end

        create_table :active_storage_attachments do |t|
          t.string     :name,     null: false
          t.references :record,   null: false, polymorphic: true, index: false
          t.references :blob,     null: false

          t.datetime :created_at, null: false

          t.index [:record_type, :record_id, :name, :blob_id],
                  name: 'index_active_storage_attachments_uniqueness',
                  unique: true
        end
      end
    end

    ApplicationRecord
  end

  before { app }

  let(:configuration_options) { {} }

  before(:each) do
    # Prevent extra spans during tests
    Datadog.configure do |c|
      c.use :active_storage, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    ClimateControl.modify('USE_ACTIVE_STORAGE' => 'true') do
      Datadog.registry[:active_record].reset_configuration!
      example.run
      Datadog.registry[:active_record].reset_configuration!
    end
  end

  # From:
  # https://github.com/rails/rails/blob/2a3f8a29e5d7d17a0448fa47fd756c8d11b175b1/activestorage/app/models/active_storage/blob.rb#L64
  # https://github.com/rails/rails/blob/06c94818d640d13efecc722c4ec8c9c5ea2a99b0/activestorage/app/models/active_storage/blob.rb#L104
  def create_blob(data: 'Hello world!', filename: 'hello.txt', content_type: 'text/plain', identify: true, record: nil)
    if Rails.version >= '6.0'
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(data),
        filename: filename,
        content_type: content_type,
        identify: identify,
        record: record
      )
    else
      ActiveStorage::Blob.create_after_upload!(
        io: StringIO.new(data),
        filename: filename,
        content_type: content_type
      )
    end
  end

  context 'when query is made' do
    # This creates an `upload` event, but we are writing locally to disk
    # from: https://github.com/rails/rails/blob/9492339979e94570dee00d071be0ef255065837a/activestorage/lib/active_storage/attached/one.rb#L28
    before(:each) do
      blob = create_blob(filename: 'testfile.jpg')
      Article.create(title: 'ok').image.attach(blob)
    end

    let(:span) do
      spans.find do |s|
        s.service == 'active_storage'
      end
    end

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', false

    it 'calls the instrumentation when is used standalone' do
      # A.count
      expect(span.service).to eq('active_storage')
      expect(span.name).to eq('active_storage.action')
      expect(span.span_type).to eq('http')
      expect(span.resource.strip).to eq('upload Disk')
      expect(span.get_tag('active_storage.key')).to_not be(nil)
      expect(span.get_tag('active_record.service')).to eq(nil)
    end
  end
end
