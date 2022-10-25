# typed: ignore

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/propagation/sql_comment'

require 'ddtrace'
require 'mysql2'

RSpec.describe 'Mysql2::Client patcher' do
  let(:service_name) { 'my-sql' }
  let(:configuration_options) { { service_name: service_name } }

  let(:client) do
    Mysql2::Client.new(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_MYSQL_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_MYSQL_PORT') { '3306' } }
  let(:database) { ENV.fetch('TEST_MYSQL_DB') { 'mysql' } }
  let(:username) { ENV.fetch('TEST_MYSQL_USER') { 'root' } }
  let(:password) { ENV.fetch('TEST_MYSQL_PASSWORD') { 'root' } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :mysql2, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:mysql2].reset_configuration!
    example.run
    Datadog.registry[:mysql2].reset_configuration!
  end

  describe 'tracing' do
    describe '#query' do
      context 'when the tracer is disabled' do
        before { tracer.enabled = false }

        it 'does not write spans' do
          client.query('SELECT 1')
          expect(spans).to be_empty
        end
      end

      context 'when the client is configured directly' do
        let(:service_override) { 'mysql-override' }

        before do
          Datadog.configure_onto(client, service_name: service_override)
          client.query('SELECT 1')
        end

        it 'produces a trace with service override' do
          expect(spans.count).to eq(1)
          expect(span.service).to eq(service_override)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
        end
      end

      context 'when a successful query is made' do
        before { client.query('SELECT 1') }

        it 'produces a trace' do
          expect(spans.count).to eq(1)
          expect(span.get_tag('mysql2.db.name')).to eq(database)
          expect(span.get_tag('out.host')).to eq(host)
          expect(span.get_tag('out.port')).to eq(port)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('mysql2')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('query')
        end

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Mysql2::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span' do
          let(:peer_hostname) { host }
        end

        it_behaves_like 'measured span for integration', false
      end

      context 'when a failed query is made' do
        before { expect { client.query('SELECT INVALID') }.to raise_error(Mysql2::Error) }

        it 'traces failed queries' do
          expect(spans.count).to eq(1)
          expect(span.status).to eq(1)
          expect(span.get_tag('db.system')).to eq('mysql')
          expect(span.get_tag('error.msg'))
            .to eq("Unknown column 'INVALID' in 'field list'")
        end
      end

      context 'when sql comment propagation' do
        let(:sql_statement) { 'SELECT 1' }

        subject { client.query(sql_statement) }

        shared_examples_for 'propagated with sql comment propagation' do |mode, span_op_name|
          it "propagates with mode: #{mode}" do
            expect(Datadog::Tracing::Contrib::Propagation::SqlComment::Mode)
              .to receive(:new).with(mode).and_return(propagation_mode)

            subject
          end

          it 'decorates the span operation' do
            expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:annotate!).with(
              a_span_operation_with(name: span_op_name),
              propagation_mode
            )
            subject
          end

          it 'prepends sql comment to the sql statement' do
            expect(Datadog::Tracing::Contrib::Propagation::SqlComment).to receive(:prepend_comment).with(
              sql_statement,
              a_span_operation_with(name: span_op_name),
              propagation_mode,
              tags: { dddbs: 'my-sql' }
            ).and_call_original

            subject
          end
        end

        context 'when default `disabled`' do
          it_behaves_like 'propagated with sql comment propagation', 'disabled', 'mysql2.query' do
            let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('disabled') }
          end
        end

        context 'when ENV variable `DD_TRACE_SQL_COMMENT_PROPAGATION_MODE` is provided' do
          around do |example|
            ClimateControl.modify(
              'DD_TRACE_SQL_COMMENT_PROPAGATION_MODE' => 'service',
              &example
            )
          end

          it_behaves_like 'propagated with sql comment propagation', 'service', 'mysql2.query' do
            let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new('service') }
          end
        end

        %w[disabled service full].each do |mode|
          context "when `sql_comment_propagation`` is configured to #{mode}" do
            let(:configuration_options) do
              { sql_comment_propagation: mode, service_name: 'my-sql' }
            end

            it_behaves_like 'propagated with sql comment propagation', mode, 'mysql2.query' do
              let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new(mode) }
            end
          end
        end
      end
    end
  end
end
