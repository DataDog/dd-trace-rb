require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'active_record'

if PlatformHelpers.jruby?
  require 'activerecord-jdbc-adapter'
else
  require 'pg'
end

RSpec.describe 'ActiveRecord async query instrumentation' do
  let(:application_record) do
    stub_const('ApplicationRecord', Class.new(ActiveRecord::Base)).tap do |klass|
      klass.abstract_class = true
    end
  end
  let!(:widget_class) { stub_const('Widget', Class.new(application_record)) }

  before do
    skip 'Test applies only to Active Record 7.0 or higher' if ActiveRecord.version < '7.0.0'

    # Reset options (that might linger from other tests)
    Datadog.configuration.tracing[:active_record].reset!

    Datadog.configure do |c|
      c.tracing.instrument :concurrent_ruby
      c.tracing.instrument :active_record
      c.tracing.instrument :pg
    end

    raise_on_rails_deprecation!

    ActiveRecord.async_query_executor = :global_thread_pool

    # Connect the Widget database
    root_pw = ENV.fetch('TEST_POSTGRES_ROOT_PASSWORD', 'postgres')
    host = ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1')
    port = ENV.fetch('TEST_POSTGRES_PORT', '5432')
    db = ENV.fetch('TEST_POSTGRES_DB', 'postgres')
    ActiveRecord::Base.establish_connection("postgresql://postgres:#{root_pw}@#{host}:#{port}/#{db}?pool=1")

    begin
      widget_class.count
    rescue ActiveRecord::StatementInvalid
      widget_class.connection.create_table 'widgets', force: :cascade do |t|
        t.string   'title'
        t.datetime 'created_at', null: false
        t.datetime 'updated_at', null: false
      end

      # Prevent extraneous spans from showing up
      async_count
    end

    widget_class.create!(title: 'test')

    clear_traces!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:concurrent_ruby].reset_configuration!
    Datadog.registry[:active_record].reset_configuration!
    Datadog.registry[:pg].reset_configuration!
    example.run
    Datadog.registry[:active_record].reset_configuration!
    Datadog.registry[:concurrent_ruby].reset_configuration!
    Datadog.registry[:pg].reset_configuration!
  end

  after { widget_class.delete_all }

  it 'propagates context to the async executor thread' do
    root_trace = nil

    Datadog::Tracing.trace("async_query.test") do |_span, trace|
      root_trace = trace

      async_count
    end

    # Ensure the async executor thread pool is shut down, to avoid leaking threads
    widget_class.connection_pool.async_executor.composited_executor.shutdown

    expect(spans).to include(
      an_object_having_attributes(name: 'async_query.test', trace_id: root_trace.id),
      an_object_having_attributes(name: 'pg.exec.params', trace_id: root_trace.id),
    )
  end

  private

  # Force the promise to resolve, ensuring the async executor is used at the right time
  def async_count
    widget_class.async_count.value
  end
end
