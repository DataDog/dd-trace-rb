require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'time'
require 'sequel'
require 'ddtrace'
require 'datadog/tracing/contrib/sequel/integration'

RSpec.describe 'Sequel instrumentation' do
  let(:configuration_options) { {} }
  let(:sequel) do
    Sequel.connect(sequel_connection_string).tap do |db|
      Datadog.configure_onto(db)
    end
  end

  let(:sequel_connection_string) do
    if PlatformHelpers.jruby?
      "jdbc:#{connection_string}"
    else
      connection_string
    end
  end

  before do
    skip('Sequel not compatible.') unless Datadog::Tracing::Contrib::Sequel::Integration.compatible?

    # Patch Sequel
    Datadog.configure do |c|
      c.tracing.instrument :sequel, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sequel].reset_configuration!
    Sequel::DATABASES.each(&:disconnect)
    example.run
    Datadog.registry[:sequel].reset_configuration!
  end

  shared_context 'instrumented queries' do
    before do
      sequel.create_table!(:tbl) do # Drops table before creating if already exists
        String :name
      end

      clear_traces!
    end

    let(:normalized_adapter) { defined?(super) ? super() : adapter }

    describe 'Sequel::Database.run' do
      shared_context 'query executed through a Sequel::Database object' do
        before { sequel.run(query) }

        let(:span) { spans.first }

        it 'traces the command' do
          expect(span.name).to eq('sequel.query')
          # Expect it to be the normalized adapter name.
          expect(span.service).to eq(normalized_adapter)
          expect(span.span_type).to eq('sql')
          expect(span.get_tag('sequel.db.vendor')).to eq(normalized_adapter)
          # Expect non-quantized query: agent does SQL quantization.
          expect(span.resource).to eq(expected_query)
          expect(span.status).to eq(0)
          expect(span.parent_id).to eq(0)

          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sequel')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Sequel::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Sequel::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) do
            if PlatformHelpers.jruby?
              nil # TODO: Extract host for Sequel with JDBC
            else
              host
            end
          end
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'with query provided as a string' do
        it_behaves_like 'query executed through a Sequel::Database object' do
          let(:query) { "SELECT * FROM tbl WHERE name = 'foo'" }
          let(:expected_query) { query }
        end
      end

      context 'with query provided as complex expression' do
        it_behaves_like 'query executed through a Sequel::Database object' do
          let(:query) { Sequel.lit('SELECT * FROM tbl WHERE name = :var', var: 'foo') }
          let(:expected_query) { sequel.literal(query) }
        end
      end
    end

    describe 'when queried through a Sequel::Dataset' do
      let(:process_span) { spans[0] }
      let(:publish_span) { spans[1] }
      let(:sequel_cmd1_span) { spans[2] }
      let(:sequel_cmd2_span) { spans[3] }
      let(:sequel_cmd3_span) { spans[4] }
      let(:sequel_internal_spans) { spans[5..-1] }

      before do
        tracer.trace('publish') do |span|
          span.service = 'webapp'
          span.resource = '/index'
          tracer.trace('process') do |subspan|
            subspan.service = 'datalayer'
            subspan.resource = 'home'
            sequel[:tbl].insert(name: 'data1')
            sequel[:tbl].insert(name: 'data2')
            data = sequel[:tbl].select.to_a
            expect(data.length).to eq(2)
            data.each do |row|
              expect(row[:name]).to match(/^data.$/)
            end
          end
        end
      end

      it do
        expect(spans).to have_at_least(5).items

        # Check publish span
        expect(publish_span.name).to eq('publish')
        expect(publish_span.service).to eq('webapp')
        expect(publish_span.resource).to eq('/index')
        expect(publish_span.span_id).to_not eq(publish_span.trace_id)
        expect(publish_span.parent_id).to eq(0)

        # Check process span
        expect(process_span.name).to eq('process')
        expect(process_span.service).to eq('datalayer')
        expect(process_span.resource).to eq('home')
        expect(process_span.parent_id).to eq(publish_span.span_id)
        expect(process_span.trace_id).to eq(publish_span.trace_id)

        # Check each command span
        [
          [sequel_cmd1_span, "INSERT INTO tbl (name) VALUES ('data1')"],
          [sequel_cmd2_span, "INSERT INTO tbl (name) VALUES ('data2')"],
          [sequel_cmd3_span, 'SELECT * FROM tbl'],
          # Internal queries run by Sequel (e.g. 'SELECT version()').
          # We don't care about their content, only that they are
          # correctly tagged.
          *sequel_internal_spans.map { |span| [span, nil] }
        ].each do |span, query|
          expect(span.name).to eq('sequel.query')
          # Expect it to be the normalized adapter name.
          expect(span.service).to eq(normalized_adapter)
          expect(span.span_type).to eq('sql')
          expect(span.get_tag('sequel.db.vendor')).to eq(normalized_adapter)
          expect(span.status).to eq(0)

          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sequel')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')

          # We then match `query` and `trace_id` for the statements under test.
          # Skip for internal Sequel queries.
          next unless query

          # Expect non-quantized query: agent does SQL quantization.
          expect(span.resource).to match_normalized_sql(start_with query)

          expect(span.parent_id).to eq(process_span.span_id)
          expect(span.trace_id).to eq(publish_span.trace_id)
        end
      end

      it_behaves_like 'analytics for integration' do
        # Check one of the command spans at random
        let(:span) { spans[2..5].sample }
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Sequel::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Sequel::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false do
        let(:span) { spans[2..5].sample }
      end
    end

    describe 'with a prepared statement' do
      subject(:run_prepared_statement) { prepared_statement.call(n: 'foo') }

      let(:prepared_statement) { sequel[:tbl].where(name: :$n).prepare(:select, :prepared_name) }

      let(:span) { spans.first }

      it do
        run_prepared_statement

        expect(span.name).to eq('sequel.query')
        # Expect it to be the normalized adapter name.
        expect(span.service).to eq(normalized_adapter)
        expect(span.span_type).to eq('sql')
        expect(span.get_tag('sequel.db.vendor')).to eq(normalized_adapter)
        expect(span.get_tag('sequel.prepared.name')).to eq('prepared_name')
        # Expect non-quantized query: agent does SQL quantization.
        expect(span.resource).to match_normalized_sql('SELECT * FROM tbl WHERE (name = ?)')
        expect(span.status).to eq(0)
        expect(span.parent_id).to eq(0)
      end
    end
  end

  describe 'with a SQLite database' do
    let(:connection_string) { 'sqlite::memory:' }
    let(:adapter) { 'sqlite' }
    let(:host) { nil }

    it_behaves_like 'instrumented queries'
  end

  describe 'with a MySQL database' do
    let(:connection_string) do
      user = ENV.fetch('TEST_MYSQL_USER', 'root')
      password = ENV.fetch('TEST_MYSQL_PASSWORD', 'root')
      port = ENV.fetch('TEST_MYSQL_PORT', '3306')
      db = ENV.fetch('TEST_MYSQL_DB', 'mysql')
      "#{adapter}://#{host}:#{port}/#{db}?user=#{user}&password=#{password}"
    end
    let(:host) { ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1') }
    let(:adapter) do
      if PlatformHelpers.jruby?
        'mysql'
      else
        'mysql2'
      end
    end

    it_behaves_like 'instrumented queries'
  end

  describe 'with a PostgreSQL database' do
    let(:connection_string) do
      user = ENV.fetch('TEST_POSTGRES_USER', 'postgres')
      password = ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres')
      port = ENV.fetch('TEST_POSTGRES_PORT', 5432)
      db = ENV.fetch('TEST_POSTGRES_DB', 'postgres')
      "#{adapter}://#{host}:#{port}/#{db}?user=#{user}&password=#{password}"
    end
    let(:host) { ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1') }
    let(:normalized_adapter) { 'postgres' }
    let(:adapter) { 'postgresql' }

    it_behaves_like 'instrumented queries'
  end
end
