require 'ddtrace/contrib/integration_examples'
require 'spec_helper'

require 'time'
require 'sequel'
require 'ddtrace'
require 'ddtrace/contrib/sequel/patcher'

RSpec.describe 'Sequel configuration' do
  let(:tracer) { get_test_tracer }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
    skip unless Datadog::Contrib::Sequel::Integration.compatible?
  end

  describe 'for a SQLite database' do
    let(:sequel) do
      Sequel.sqlite(':memory:').tap do |db|
        db.create_table(:table) do
          String :name
        end
      end
    end

    def perform_query!
      sequel[:table].insert(name: 'data1')
    end

    describe 'when configured' do
      subject(:query) { perform_query! }
      after(:each) { Datadog.configuration[:sequel].reset! }

      context 'only with defaults' do
        before { Datadog.configure { |c| c.use :sequel, tracer: tracer } }

        it 'normalizes adapter name' do
          subject
          expect(span.service).to eq('sqlite')
        end

        it_behaves_like 'a peer service span'
      end

      context 'with options set via #use' do
        let(:service_name) { 'my-sequel' }

        before { Datadog.configure { |c| c.use :sequel, tracer: tracer, service_name: service_name } }

        it do
          subject
          expect(span.service).to eq(service_name)
        end

        it_behaves_like 'a peer service span'
      end

      context 'with options set on Sequel::Database' do
        let(:service_name) { 'custom-sequel' }

        before do
          Datadog.configure { |c| c.use :sequel, tracer: tracer }
          Datadog.configure(sequel, service_name: service_name)
        end

        it do
          subject
          expect(span.service).to eq(service_name)
        end

        it_behaves_like 'a peer service span'
      end

      # NOTE: This test really only works when run in isolation.
      #       It relies on Sequel not being patched, and there's
      #       no way to unpatch it once its happened in other tests.
      context 'after the database has been initialized' do
        before do
          sequel
          Datadog.configure { |c| c.use :sequel, tracer: tracer }
          perform_query!
        end

        it do
          expect(span.service).to eq('sqlite')
        end

        it_behaves_like 'a peer service span'
      end
    end
  end
end
