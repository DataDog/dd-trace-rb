require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails database' do
  include_context 'Rails test application'

  let(:database_service) { adapter_name }

  before do
    Datadog.configure do |c|
      c.use :rails, database_service: database_service
    end
  end

  before { app }

  before do
    stub_const('Article', Class.new(ActiveRecord::Base))

    Article.count # Ensure warm up queries are executed before tests
    clear_spans
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
      expect(adapter_port.to_s).to eq(span.get_tag('out.port'))
      expect(span.resource).to include('SELECT COUNT(*) FROM')
      # ensure that the sql.query tag is not set
      expect(span.get_tag('sql.query')).to be_nil
    end
  end

  context 'on record creation' do
    before do
      Article.create(title: 'Instantiation test')
      clear_spans
    end

    context 'with instantiation support' do
      before { skip unless Datadog::Contrib::ActiveRecord::Events::Instantiation.supported? }

      subject! { Article.all.entries }

      it do
        expect(spans).to have(2).items

        span, = spans
        expect(span.name).to eq('active_record.instantiation')
        expect(span.span_type).to eq('custom')
        # Because no parent, and doesn't belong to database service
        expect(span.service).to eq('active_record')
        expect(span.resource).to eq('Article')
        expect(span.get_tag('active_record.instantiation.class_name')).to eq('Article')
        expect(span.get_tag('active_record.instantiation.record_count')).to eq('1')
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
          expect(instantiation_span.service).to eq(parent_span.service) # Because within parent
          expect(instantiation_span.resource).to eq('Article')
          expect(instantiation_span.get_tag('active_record.instantiation.class_name')).to eq('Article')
          expect(instantiation_span.get_tag('active_record.instantiation.record_count')).to eq('1')
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

        clear_spans

        Article.count
        expect(span.get_tag('active_record.db.cached')).to eq('true')
      end
    end
  end

  context 'with custom database_service' do
    let(:database_service) { 'customer-db' }

    it 'doing a database call uses the proper service name if it is changed' do
      Article.count

      expect(span.service).to eq('customer-db')
    end
  end
end
