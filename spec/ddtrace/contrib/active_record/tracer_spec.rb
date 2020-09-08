require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/integration_examples'
require 'ddtrace'

require_relative 'app'

RSpec.describe 'ActiveRecord instrumentation' do
  let(:configuration_options) { {} }

  before(:each) do
    # Prevent extra spans during tests
    Article.count

    # Reset options (that might linger from other tests)
    Datadog.configuration[:active_record].reset!

    Datadog.configure do |c|
      c.use :active_record, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:active_record].reset_configuration!
    example.run
    Datadog.registry[:active_record].reset_configuration!
  end

  context 'when query is made' do
    before(:each) { Article.count }

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_SAMPLE_RATE }
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
    end
  end
end
