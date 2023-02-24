require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'ddtrace'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require_relative 'app'

RSpec.describe 'ActiveRecord instrumentation' do
  let(:configuration_options) { {} }

  before do
    # Prevent extra spans during tests
    Article.count

    # Reset options (that might linger from other tests)
    Datadog.configuration.tracing[:active_record].reset!

    Datadog.configure do |c|
      c.tracing.instrument :active_record, configuration_options
    end

    raise_on_rails_deprecation!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:active_record].reset_configuration!
    example.run
    Datadog.registry[:active_record].reset_configuration!
  end

  context 'when query is made' do
    before { Article.count }

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'a peer service span'

    it_behaves_like 'measured span for integration', false

    it 'calls the instrumentation when is used standalone' do
      expect(span.service).to eq('mysql2')
      expect(span.name).to eq('mysql2.query')
      expect(span.span_type).to eq('sql')
      expect(span.resource.strip).to eq('SELECT COUNT(*) FROM `articles`')
      expect(span.get_tag('active_record.db.vendor')).to eq('mysql2')
      expect(span.get_tag('active_record.db.name')).to eq('mysql')
      expect(span.get_tag('active_record.db.cached')).to eq(nil)
      expect(span.get_tag('out.host')).to eq(ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'))
      expect(span.get_tag('out.port')).to eq(ENV.fetch('TEST_MYSQL_PORT', 3306).to_f)
      expect(span.get_tag('sql.query')).to eq(nil)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('active_record')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('sql')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('mysql2')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
        .to eq(ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'))
    end

    context 'and service_name' do
      context 'is not set' do
        it { expect(span.service).to eq('mysql2') }
      end

      context 'is set' do
        let(:service_name) { 'test_active_record' }
        let(:configuration_options) { super().merge(service_name: service_name) }

        it { expect(span.service).to eq(service_name) }
      end

      context 'with a custom configuration' do
        context 'with the maraka gem' do
          before do
            if PlatformHelpers.jruby?
              skip("JRuby doesn't support ObjectSpace._id2ref, which is required for makara connection lookup.")
            end

            @original_config = if defined?(::ActiveRecord::Base.connection_db_config)
                                 ::ActiveRecord::Base.connection_db_config
                               else
                                 ::ActiveRecord::Base.connection_config
                               end

            # Set up makara
            require 'makara'
            require 'active_record/connection_adapters/makara_mysql2_adapter'

            # Set up ActiveRecord
            ::ActiveRecord::Base.establish_connection(config)
            ::ActiveRecord::Base.logger = Logger.new(nil)

            # Warm it up
            Article.count
            clear_traces!

            Datadog.configure do |c|
              c.tracing.instrument :active_record, service_name: 'bad-no-match'
              c.tracing.instrument :active_record,
                describes: { makara_role: primary_role },
                service_name: primary_service_name
              c.tracing.instrument :active_record,
                describes: { makara_role: secondary_role },
                service_name: secondary_service_name
            end
          end

          after { ::ActiveRecord::Base.establish_connection(@original_config) if @original_config }

          let(:primary_service_name) { 'primary-service' }
          let(:secondary_service_name) { 'secondary-service' }

          # makara changed their internal role names from `master/slave` to `primary/secondary` in 0.6.0.
          let(:legacy_role_naming) { Gem::Version.new(::Makara::VERSION.to_s) < Gem::Version.new('0.6.0.pre') }
          let(:primary_role) { legacy_role_naming ? 'master' : 'primary' }
          let(:secondary_role) { legacy_role_naming ? 'slave' : 'replica' }

          let(:config) do
            YAML.safe_load(<<-YAML)['test']
          test:
            adapter: 'mysql2_makara'
            database: '#{ENV.fetch('TEST_MYSQL_DB', 'mysql')}'
            username: 'root'
            host: '#{ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1')}'
            password: '#{ENV.fetch('TEST_MYSQL_ROOT_PASSWORD', 'root')}'
            port: '#{ENV.fetch('TEST_MYSQL_PORT', '3306')}'

            makara:
              connections:
                - role: #{primary_role}
                - role: #{secondary_role}
                - role: #{secondary_role}
            YAML
          end

          context 'and a master write operation' do
            it 'matches replica configuration' do
              # SHOW queries are executed on master
              ActiveRecord::Base.connection.execute('SHOW TABLES')

              expect(spans).to have_at_least(1).item
              spans.each do |span|
                expect(span.service).to eq(primary_service_name)
              end
            end
          end

          context 'and a replica read operation' do
            it 'matches replica configuration' do
              # SELECT queries are executed on replicas
              Article.count

              expect(span.service).to eq(secondary_service_name)
            end
          end
        end
      end
    end
  end
end
