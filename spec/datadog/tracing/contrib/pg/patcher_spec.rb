require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/sql_comment_propagation_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'datadog/tracing/contrib/propagation/sql_comment/mode'

require 'ddtrace'
require 'pg'

RSpec.describe 'PG::Connection patcher' do
  let(:service_name) { 'pg' }
  let(:configuration_options) { { service_name: service_name } }

  let(:conn) do
    PG::Connection.new(
      host: host,
      port: port,
      dbname: dbname,
      user: user,
      password: password
    )
  end

  let(:host) { ENV.fetch('TEST_POSTGRES_HOST') { '127.0.0.1' } }
  let(:port) { ENV.fetch('TEST_POSTGRES_PORT') { '5432' } }
  let(:dbname) { ENV.fetch('TEST_POSTGRES_DB') { 'postgres' } }
  let(:user) { ENV.fetch('TEST_POSTGRES_USER') { 'postgres' } }
  let(:password) { ENV.fetch('TEST_POSTGRES_PASSWORD') { 'postgres' } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :pg, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:pg].reset_configuration!
    example.run
    Datadog.registry[:pg].reset_configuration!
  end

  after do
    conn.close
  end

  describe 'tracing' do
    describe '#exec' do
      let(:sql_statement) { 'SELECT 1;' }

      context 'when without a given block' do
        subject(:exec) { conn.exec(sql_statement) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec'

          it 'produces a trace with service override' do
            exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec'

          it 'produces a trace' do
            exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec', error: PG::Error

          it 'traces failed queries' do
            expect { exec }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when with a given block' do
        subject(:exec) do
          conn.exec(sql_statement) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec'

          it 'produces a trace with service override' do
            exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec'

          it 'produces a trace' do
            exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec', error: PG::Error

          it 'traces failed queries' do
            expect { exec }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#exec_params' do
      let(:sql_statement) { 'SELECT $1::int;' }

      context 'when without a given block' do
        subject(:exec_params) { conn.exec_params(sql_statement, [1]) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec_params

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params'

          it 'produces a trace with service override' do
            exec_params

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params'

          it 'produces a trace' do
            exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:exec_params) { conn.exec_params(sql_statement, ['INVALID']) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { exec_params }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when given a block' do
        subject(:exec_params) do
          conn.exec_params(sql_statement, [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec_params

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params'

          it 'produces a trace with service override' do
            exec_params

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params'

          it 'produces a trace' do
            exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:exec_params) do
            conn.exec_params(sql_statement, ['INVALID']) do |_pg_result|
              # Do something with PG::Result
            end
          end

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { exec_params }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#exec_prepared' do
      before { conn.prepare('prepared select 1', 'SELECT $1::int') }

      context 'when without a given block' do
        subject(:exec_prepared) { conn.exec_prepared('prepared select 1', [1]) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          it 'traces failed queries' do
            expect { conn.exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
            subject { conn.exec_prepared('invalid prepared select 1', ['INVALID']) }
          end
        end
      end

      context 'when given a block' do
        subject(:exec_prepared) do
          conn.exec_prepared('prepared select 1', [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          subject(:exec_prepared) do
            conn.exec_prepared('invalid prepared select 1', ['INVALID']) do |_pg_result|
              # Do something with PG::Result
            end
          end

          it 'traces failed queries' do
            expect { exec_prepared }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#async_exec' do
      let(:sql_statement) { 'SELECT 1;' }

      context 'when without given block' do
        subject(:async_exec) { conn.async_exec(sql_statement) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec'

          it 'produces a trace with service override' do
            async_exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec'

          it 'produces a trace' do
            async_exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          subject(:async_exec) { conn.async_exec(sql_statement) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec', error: PG::Error

          it 'traces failed queries' do
            expect { async_exec }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when given a block' do
        subject(:async_exec) do
          conn.async_exec(sql_statement) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec'

          it 'produces a trace with service override' do
            async_exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec'

          it 'produces a trace' do
            async_exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          subject(:async_exec) do
            conn.async_exec(sql_statement) do |_pg_result|
              # Do something with PG::Result
            end
          end

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec', error: PG::Error

          it 'traces failed queries' do
            expect { async_exec }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#async_exec_params' do
      before do
        skip('pg < 1.1.0 does not support #async_exec_params') if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
      end

      let(:sql_statement) { 'SELECT $1::int;' }

      context 'when without given a block' do
        subject(:async_exec_params) { conn.async_exec_params(sql_statement, [1]) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec_params

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params'

          it 'produces a trace with service override' do
            async_exec_params

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params'

          it 'produces a trace' do
            async_exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:async_exec_params) { conn.async_exec_params(sql_statement, ['INVALID']) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { async_exec_params }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when given a block' do
        subject(:async_exec_params) do
          conn.async_exec_params(sql_statement, [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec_params

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params'

          it 'produces a trace with service override' do
            async_exec_params

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params'

          it 'produces a trace' do
            async_exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:async_exec_params) { conn.async_exec_params(sql_statement, ['INVALID']) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.async.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { async_exec_params }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#async_exec_prepared' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #async_exec_prepared')
        end
        conn.prepare('prepared select 1', 'SELECT $1::int')
      end

      context 'when without given block' do
        subject(:async_exec_prepared) { conn.async_exec_prepared('prepared select 1', [1]) }
        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            async_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            async_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          it 'traces failed queries' do
            expect { conn.async_exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
            subject { conn.async_exec_prepared('invalid prepared select 1', ['INVALID']) }
          end
        end
      end

      context 'when given a block' do
        subject(:async_exec_prepared) do
          conn.async_exec_prepared('prepared select 1', [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            async_exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            async_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            async_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_ASYNC_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { async_exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { async_exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { async_exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          subject(:async_exec_prepared) do
            conn.async_exec_prepared('invalid prepared select 1', ['INVALID']) do |_pg_result|
              # Do something with PG::Result
            end
          end

          it 'traces failed queries' do
            expect { async_exec_prepared }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#sync_exec' do
      before do
        if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
          skip('pg < 1.1.0 does not support #async_exec_prepared')
        end
      end

      let(:sql_statement) { 'SELECT 1;' }

      context 'when without a given block' do
        subject(:sync_exec) { conn.sync_exec(sql_statement) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec'

          it 'produces a trace with service override' do
            sync_exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec'

          it 'produces a trace' do
            sync_exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec', error: PG::Error

          it 'traces failed queries' do
            expect { sync_exec }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when given a block' do
        subject(:sync_exec) do
          conn.sync_exec(sql_statement) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec

            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec'

          it 'produces a trace with service override' do
            sync_exec

            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec'

          it 'produces a trace' do
            sync_exec

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT INVALID' }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec', error: PG::Error

          it 'traces failed queries' do
            expect { sync_exec }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('column "invalid" does not exist'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#sync_exec_params' do
      before do
        skip('pg < 1.1.0 does not support #sync_exec_params') if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
      end

      let(:sql_statement) { 'SELECT $1::int;' }

      context 'when without given block' do
        subject(:sync_exec_params) { conn.sync_exec_params(sql_statement, [1]) }

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec_params
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params'

          it 'produces a trace with service override' do
            sync_exec_params
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params'

          it 'produces a trace' do
            sync_exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:sync_exec_params) { conn.sync_exec_params(sql_statement, ['INVALID']) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { sync_exec_params }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end

      context 'when given a block' do
        subject(:sync_exec_params) do
          conn.sync_exec_params(sql_statement, [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end

        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec_params
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_name) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_name) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params'

          it 'produces a trace with service override' do
            sync_exec_params
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_name)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_name)
          end
        end

        context 'when a successful query is made' do
          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params'

          it 'produces a trace' do
            sync_exec_params

            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PARAMS)
            expect(span.resource).to eq(sql_statement)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec_params }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec_params }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec_params }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          let(:sql_statement) { 'SELECT $1;' }

          subject(:sync_exec_params) { conn.sync_exec_params(sql_statement, ['INVALID']) }

          it_behaves_like 'with sql comment propagation', span_op_name: 'pg.sync.exec.params', error: PG::Error

          it 'traces failed queries' do
            expect { sync_exec_params }.to raise_error(PG::Error)

            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(include('ERROR') & include('could not determine data type of parameter $1'))
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end

    describe '#sync_exec_prepared' do
      before do
        skip('pg < 1.1.0 does not support #sync_exec_prepared') if Gem::Version.new(PG::VERSION) < Gem::Version.new('1.1.0')
        conn.prepare('prepared select 1', 'SELECT $1::int')
      end

      context 'when without a given block' do
        subject(:sync_exec_prepared) { conn.sync_exec_prepared('prepared select 1', [1]) }
        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            sync_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            sync_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          it 'traces failed queries' do
            expect { conn.sync_exec_prepared('invalid prepared select 1', ['INVALID']) }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
            subject { conn.sync_exec_prepared('invalid prepared select 1', ['INVALID']) }
          end
        end
      end

      context 'when given a block' do
        subject(:sync_exec_prepared) do
          conn.sync_exec_prepared('prepared select 1', [1]) do |_pg_result|
            # Do something with PG::Result
          end
        end
        context 'when the tracer is disabled' do
          before { tracer.enabled = false }

          it 'does not write spans' do
            sync_exec_prepared
            expect(spans).to be_empty
          end
        end

        context 'when the tracer is configured directly' do
          let(:service_override) { 'pg-override' }

          before { Datadog.configure_onto(conn, service_name: service_override) }

          it 'produces a trace with service override' do
            sync_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.service).to eq(service_override)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE)).to eq(service_override)
          end
        end

        context 'when a successful query is made' do
          statement_name = 'prepared select 1'

          it 'produces a trace' do
            sync_exec_prepared
            expect(spans.count).to eq(1)
            expect(span.name).to eq(Datadog::Tracing::Contrib::Pg::Ext::SPAN_SYNC_EXEC_PREPARED)
            expect(span.resource).to eq(statement_name)
            expect(span.service).to eq('pg')
            expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::SQL::TYPE)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_KIND))
              .to eq(Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)
            expect(span.get_tag(Datadog::Tracing::Contrib::Pg::Ext::TAG_DB_NAME)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_COMPONENT)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::TAG_OPERATION_QUERY)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
              .to eq(Datadog::Tracing::Contrib::Pg::Ext::DEFAULT_PEER_SERVICE_NAME)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_INSTANCE)).to eq(dbname)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_USER)).to eq(user)
            expect(span.get_tag('db.system')).to eq('postgresql')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME)).to eq(host)
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_DESTINATION_PORT)).to eq(port.to_i)
            expect(span.get_tag(Datadog::Tracing::Contrib::Ext::DB::TAG_ROW_COUNT)).to eq(1)
          end

          it_behaves_like 'analytics for integration' do
            before { sync_exec_prepared }
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Pg::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span' do
            before { sync_exec_prepared }
            let(:peer_hostname) { host }
          end

          it_behaves_like 'measured span for integration', false do
            before { sync_exec_prepared }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME' do
            let(:configuration_options) { {} }
          end
        end

        context 'when a failed query is made' do
          subject(:sync_exec_prepared) do
            conn.sync_exec_prepared('invalid prepared select 1', ['INVALID']) do |_pg_result|
              # Do something with PG::Result
            end
          end

          it 'traces failed queries' do
            expect { sync_exec_prepared }.to raise_error(PG::Error)
            expect(spans.count).to eq(1)
            expect(span).to have_error
            expect(span).to have_error_message(
              include('ERROR') & include('prepared statement "invalid prepared select 1" does not exist')
            )
          end

          it_behaves_like 'environment service name', 'DD_TRACE_PG_SERVICE_NAME', error: PG::Error do
            let(:configuration_options) { {} }
          end
        end
      end
    end
  end
end
