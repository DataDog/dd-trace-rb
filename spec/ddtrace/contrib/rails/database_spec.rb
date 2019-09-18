require 'ddtrace/contrib/rails/rails_helper'

def get_adapter_name
  Datadog::Contrib::ActiveRecord::Utils.adapter_name
end

def get_database_name
  Datadog::Contrib::ActiveRecord::Utils.database_name
end

def get_adapter_host
  Datadog::Contrib::ActiveRecord::Utils.adapter_host
end

def get_adapter_port
  Datadog::Contrib::ActiveRecord::Utils.adapter_port
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Article < ApplicationRecord
end

# TODO better method names and RSpec contexts
RSpec.describe 'Rails application' do
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]

    Datadog.configure do |c|
      c.use :rails, database_service: get_adapter_name, tracer: tracer
    end
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  before { app }

  before do
    Article.count # Ensure all warming up queries are executed before we start our test
    clear_spans
  end

  it 'active record is properly traced' do
    # make the query and assert the proper spans
    Article.count

    adapter_name = get_adapter_name
    database_name = get_database_name
    adapter_host = get_adapter_host
    adapter_port = get_adapter_port
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

  it 'active record traces instantiation' do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      begin
        Article.create(title: 'Instantiation test')
        clear_spans

        # make the query and assert the proper spans
        Article.all.entries
        expect(spans).to have(2).items

        span = spans.first
        expect(span.name).to eq('active_record.instantiation')
        expect(span.span_type).to eq('custom')
        # Because no parent, and doesn't belong to database service
        expect(span.service).to eq('active_record')
        expect(span.resource).to eq('Article')
        expect(span.get_tag('active_record.instantiation.class_name')).to eq('Article')
        expect(span.get_tag('active_record.instantiation.record_count')).to eq('1')
      ensure
        Article.delete_all
      end
    end
  end

  it 'active record traces instantiation inside parent trace' do
    if Datadog::Contrib::ActiveRecord::Events::Instantiation.supported?
      begin
        Article.create(title: 'Instantiation test')
        clear_spans

        # make the query and assert the proper spans
        tracer.trace('parent.span', service: 'parent-service') do
          Article.all.entries
        end
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
      ensure
        Article.delete_all
      end
    end
  end

  it 'active record is sets cached tag' do
    # Make sure query caching is enabled...
    Article.cache do
      # Do two queries (second should cache.)
      Article.count
      Article.count

      # Assert correct number of spans
      expect(spans).to have(2).items

      # Assert cached flag not present on first query
      expect(spans.first.get_tag('active_record.db.cached')).to be_nil

      # Assert cached flag set correctly on second query
      expect(spans.last.get_tag('active_record.db.cached')).to eq('true')
    end
  end

  it 'doing a database call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:database_service, 'customer-db')

    Article.count # Ensure all warming up queries are executed before we start our test
    clear_spans

    # make the query and assert the proper spans
    Article.count

    expect(span.service).to eq('customer-db')

    # reset the original configuration
    reset_config
  end
end
