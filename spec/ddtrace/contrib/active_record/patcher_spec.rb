require 'spec_helper'
require 'support/database_cleaner'

require 'ddtrace'
require 'ddtrace/contrib/active_record/patcher'

require_relative 'app'

RSpec.configure do |config|
  config.around(:example, :skip_when_unsupported) do |ex|
    ex.run if Gem.loaded_specs['activerecord'] \
            && Gem.loaded_specs['activerecord'].version >= Gem::Version.new('4.2')
  end
end

RSpec.describe Datadog::Contrib::ActiveRecord::Patcher, :database_cleaner do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:services) { tracer.writer.services }
  let(:configuration_options) { { tracer: tracer } }

  let(:spans) { tracer.writer.spans }

  before do
    # prepopulate db
    Article.create(title: :test)

    described_class.send(:unsubscribe_all)

    Datadog.configuration[:active_record].reset_options!
    described_class.instance_variable_set(:@patched, false)

    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :active_record, configuration_options
    end
  end

  describe 'simple query' do
    subject(:query) { Article.count }
    let(:span) { spans.first }

    shared_examples_for 'having only sql span' do
      it 'sends mysql2 service trace' do
        query

        expect(services['mysql2']).to eq('app' => 'active_record', 'app_type' => 'db')
      end

      it 'creates exactly once span' do
        query

        expect(spans.size).to eq(1)
      end

      it 'creates span describing the query' do
        query

        expect(span.service).to eq('mysql2')
        expect(span.name).to eq('mysql2.query')
        expect(span.span_type).to eq('sql')
        expect(span.resource.strip).to eq('SELECT COUNT(*) FROM `articles`')
      end

      it 'tags the span' do
        query

        expect(span.get_tag('active_record.db.vendor')).to eq('mysql2')
        expect(span.get_tag('active_record.db.name')).to eq('mysql')
        expect(span.get_tag('active_record.db.cached')).to eq(nil)
        expect(span.get_tag('out.host')).to eq(ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'))
        expect(span.get_tag('out.port')).to eq(ENV.fetch('TEST_MYSQL_PORT', 3306).to_s)
        expect(span.get_tag('sql.query')).to eq(nil)
      end
    end

    it_behaves_like 'having only sql span'

    context 'when tracing only sql events' do
      let(:configuration_options) { { tracer: tracer, features: [:trace_sql_events] } }

      it_behaves_like 'having only sql span'
    end

    context 'when tracing only instantiations' do
      let(:configuration_options) { { tracer: tracer, features: [:trace_instantiation_events] } }

      it "doesn't create any spans" do
        query

        expect(spans.size).to eq(0)
      end
    end
  end

  describe 'creating model instance' do
    let(:article) { Article.first }

    let(:sql_spans) { spans.select { |s| s.name == 'mysql2.query' } }
    let(:instantation_spans) { spans.select { |s| s.name == 'active_record.instantiation' } }

    shared_examples_for 'having sql spans' do
      it 'creates multiple spans' do
        article

        expect(sql_spans.size).to be > 0
      end

      it 'sends mysql service trace' do
        article

        expect(services['mysql2']).to eq('app' => 'active_record', 'app_type' => 'db')
      end

      it 'creates spans describing the query' do
        article

        sql_spans.each do |span|
          expect(span.service).to eq('mysql2')
          expect(span.name).to eq('mysql2.query')
          expect(span.span_type).to eq('sql')
          expect(span.resource).not_to be_nil
        end
      end

      it 'tags all spans' do
        article

        sql_spans.each do |span|
          expect(span.get_tag('active_record.db.vendor')).to eq('mysql2')
          expect(span.get_tag('active_record.db.name')).to eq('mysql')
          expect(span.get_tag('active_record.db.cached')).to eq(nil)
          expect(span.get_tag('out.host')).to eq(ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1'))
          expect(span.get_tag('out.port')).to eq(ENV.fetch('TEST_MYSQL_PORT', 3306).to_s)
          expect(span.get_tag('sql.query')).to eq(nil)
        end
      end
    end

    shared_examples_for 'having instantation span', :skip_when_unsupported do
      let(:span) { instantation_spans.first }

      it 'has exactly one instantation span' do
        article

        expect(instantation_spans.size).to eq(1)
      end

      it 'sends service trace' do
        article

        expect(services['mysql2']).to eq('app' => 'active_record', 'app_type' => 'db')
      end

      it 'creates span describing the instantiation' do
        article

        expect(span.service).to eq('active_record')
        expect(span.name).to eq('active_record.instantiation')
        expect(span.span_type).to eq('custom')
        expect(span.resource).to eq('Article')
      end

      it 'tags span' do
        article

        expect(span.get_tag('active_record.instantiation.class_name')).to eq('Article')
        expect(span.get_tag('active_record.instantiation.record_count')).to eq('1')
      end
    end

    it_behaves_like 'having sql spans'
    it_behaves_like 'having instantation span'

    context 'when tracing only sql spans' do
      let(:configuration_options) { { tracer: tracer, features: [:trace_sql_events] } }

      it_behaves_like 'having sql spans'

      it "doesn't have instantation spans" do
        article

        expect(instantation_spans.size).to eq(0)
      end
    end

    context 'when tracing only instantiations' do
      let(:configuration_options) { { tracer: tracer, features: [:trace_instantiation_events] } }

      it_behaves_like 'having instantation span'

      it "doesn't create any sql spans" do
        article

        expect(sql_spans.size).to eq(0)
      end
    end
  end

  context 'when service_name' do
    let(:query_span) { spans.first }

    context 'is not set' do
      let(:configuration_options) { super().merge(service_name: nil) }
      it 'uses default service name' do
        Article.count

        expect(query_span.service).to eq('mysql2')
      end
    end

    context 'is set' do
      let(:service_name) { 'test_active_record' }
      let(:configuration_options) { super().merge(service_name: service_name) }

      it 'uses configured service name' do
        Article.count
        expect(query_span.service).to eq(service_name)
      end
    end
  end
end
