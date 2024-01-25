require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'ddtrace'

require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require_relative 'app'

RSpec.describe 'ActiveRecord instantiation instrumentation' do
  let(:configuration_options) { {} }
  let(:article) { Article.first }

  before do
    # Create the article to be retrieved in the tests.
    Article.create!(title: 'test')

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

  context 'when a model is instantiated' do
    before { article }

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::ActiveRecord::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', true

    let(:span) do
      # First span is for SQL query, second span is for instantiation.
      expect(spans.length).to be(2)
      expect(spans.first.name).to eq('active_record.instantiation')
      expect(spans.last.name).to match(/query/)
      spans.first
    end

    it 'calls the instrumentation when is used standalone' do
      aggregate_failures do
        expect(span.service).to eq('rspec')
        expect(span.name).to eq('active_record.instantiation')
        expect(span.span_type).to eq('custom')
        expect(span.resource.strip).to eq('Article')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('active_record')
      end
    end

    context 'and service_name' do
      #it_behaves_like 'schema version span'

      context 'is not set' do
        it { expect(span.service).to eq(tracer.default_service) }
      end

      context 'is set' do
        let(:service_name) { 'test_active_record' }
        let(:configuration_options) { super().merge(service_name: service_name) }

        # Service name override in AR tracing configuration applies only to
        # the SQL query instrumentation, not to instantiation insturmentation.
        # Instantiation events always use the application's service name.
        it { expect(span.service).to eq(tracer.default_service) }
      end
    end
  end
end
