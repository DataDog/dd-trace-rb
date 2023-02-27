require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/analytics_examples'

RSpec.describe 'Rails database' do
  include_context 'Rails test application'

  let(:database_service) { adapter_name }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails
      c.tracing.instrument :active_record, service_name: database_service
    end
  end

  before { app }

  before do
    stub_const('Article', Class.new(ActiveRecord::Base))

    begin
      Article.count
    rescue ActiveRecord::StatementInvalid
      ActiveRecord::Schema.define(version: 20161003090450) do
        create_table 'articles', force: :cascade do |t|
          t.string   'title'
          t.datetime 'created_at', null: false
          t.datetime 'updated_at', null: false
        end
      end
      Article.count # Ensure warm up queries are executed before tests
    end

    clear_traces!
  end

  after { Article.delete_all }

  context 'with ActiveRecord query' do
    subject! { Article.count }

    it 'active record is properly traced' do
      expect(span.name).to eq("#{adapter_name}.query")
      expect(span.span_type).to eq('sql')
      expect(span.service).to eq(adapter_name)
      expect(span.get_tag('active_record.db.vendor')).to eq(adapter_name)
      expect(span.get_tag('active_record.db.name')).to eq(database_name)
      expect(span.get_tag('active_record.db.cached')).to be_nil
      expect(adapter_host.to_s).to eq(span.get_tag('out.host'))
      expect(adapter_port).to eq(span.get_tag('out.port'))
      expect(span.resource).to include('SELECT COUNT(*) FROM')
      # ensure that the sql.query tag is not set
      expect(span.get_tag('sql.query')).to be_nil
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_record')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('sql')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq(adapter_name)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
        .to eq(adapter_host.to_s)
    end

    it_behaves_like 'a peer service span'
  end

  context 'on record creation' do
    before do
      Article.create(title: 'Instantiation test')
      clear_traces!
    end

    context 'with instantiation support' do
      before { skip unless Datadog::Tracing::Contrib::ActiveRecord::Events::Instantiation.supported? }

      subject! { Article.all.entries }

      it_behaves_like 'measured span for integration', true do
        let(:span) { spans.find { |s| s.name == 'active_record.instantiation' } }
      end

      it do
        expect(spans).to have(2).items

        span, = spans
        expect(span.name).to eq('active_record.instantiation')
        expect(span.span_type).to eq('custom')
        # Because no parent, and doesn't belong to database service
        expect(span.service).to eq(tracer.default_service)
        expect(span.resource).to eq('Article')
        expect(span.get_tag('active_record.instantiation.class_name')).to eq('Article')
        expect(span.get_tag('active_record.instantiation.record_count')).to eq(1)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_record')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('instantiation')
      end

      context 'inside parent trace' do
        subject! do
          tracer.trace('parent.span', service: 'parent-service') do
            Article.all.entries
          end
        end

        it do
          expect(spans).to have(3).items

          parent_span = spans.find { |s| s.name == 'parent.span' }
          instantiation_span = spans.find { |s| s.name == 'active_record.instantiation' }

          expect(parent_span.service).to eq('parent-service')

          expect(instantiation_span.name).to eq('active_record.instantiation')
          expect(instantiation_span.span_type).to eq('custom')
          expect(instantiation_span.service).to eq(tracer.default_service) # Because within parent
          expect(instantiation_span.resource).to eq('Article')
          expect(instantiation_span.get_tag('active_record.instantiation.class_name')).to eq('Article')
          expect(instantiation_span.get_tag('active_record.instantiation.record_count')).to eq(1)
          expect(instantiation_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq('active_record')
          expect(instantiation_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('instantiation')
        end
      end
    end
  end

  context 'with caching' do
    it do
      # Make sure query caching is enabled
      Article.cache do
        Article.count
        expect(span.get_tag('active_record.db.cached')).to be_nil

        clear_traces!

        Article.count
        expect(span.get_tag('active_record.db.cached')).to eq('true')
      end
    end
  end

  context 'with custom database_service' do
    subject(:query) { Article.count }

    let(:database_service) { 'customer-db' }

    it 'doing a database call uses the proper service name if it is changed' do
      subject
      expect(span.service).to eq('customer-db')
    end

    it_behaves_like 'a peer service span'
  end
end
