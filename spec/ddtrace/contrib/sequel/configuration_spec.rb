require 'ddtrace/contrib/support/spec_helper'

require 'time'
require 'sequel'
require 'ddtrace'
require 'ddtrace/contrib/sequel/patcher'

RSpec.describe 'Sequel configuration' do
  before(:each) do
    skip unless Datadog::Contrib::Sequel::Integration.compatible?
  end

  let(:span) { spans.first }

  describe 'for a SQLite database' do
    let(:sequel) do
      Sequel.connect(connection_string).tap do |db|
        db.create_table(:table) do
          String :name
        end
      end
    end

    let(:connection_string) do
      if PlatformHelpers.jruby?
        'jdbc:sqlite::memory:'
      else
        'sqlite::memory:'
      end
    end

    def perform_query!
      sequel[:table].insert(name: 'data1')
    end

    describe 'when configured' do
      after(:each) { Datadog.configuration[:sequel].reset! }

      context 'only with defaults' do
        # Expect it to be the normalized adapter name.
        it do
          Datadog.configure { |c| c.use :sequel }
          perform_query!
          expect(span.service).to eq('sqlite')
        end
      end

      context 'with options set via #use' do
        let(:service_name) { 'my-sequel' }

        it do
          Datadog.configure { |c| c.use :sequel, service_name: service_name }
          perform_query!
          expect(span.service).to eq(service_name)
        end
      end

      context 'with options set on Sequel::Database' do
        let(:service_name) { 'custom-sequel' }

        it do
          Datadog.configure { |c| c.use :sequel }
          Datadog.configure(sequel, service_name: service_name)
          perform_query!
          expect(span.service).to eq(service_name)
        end
      end

      context 'after the database has been initialized' do
        # NOTE: This test really only works when run in isolation.
        #       It relies on Sequel not being patched, and there's
        #       no way to unpatch it once its happened in other tests.
        it do
          sequel
          Datadog.configure { |c| c.use :sequel }
          perform_query!
          expect(span.service).to eq('sqlite')
        end
      end
    end
  end
end
