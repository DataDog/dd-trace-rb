require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'

require 'time'
require 'sequel'
require 'ddtrace'
require 'datadog/tracing/contrib/sequel/patcher'

RSpec.describe 'Sequel configuration' do
  before do
    skip unless Datadog::Tracing::Contrib::Sequel::Integration.compatible?
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
      after { Datadog.configuration.tracing[:sequel].reset! }

      context 'only with defaults' do
        # Expect it to be the normalized adapter name.
        before do
          Datadog.configure { |c| c.tracing.instrument :sequel }
          perform_query!
        end

        it do
          expect(span.service).to eq('sqlite')
        end

        it_behaves_like 'a peer service span'
      end

      context 'with options set via #use' do
        let(:service_name) { 'my-sequel' }

        before do
          Datadog.configure { |c| c.tracing.instrument :sequel, service_name: service_name }
          perform_query!
        end

        it do
          expect(span.service).to eq(service_name)
        end

        it_behaves_like 'a peer service span'
      end

      context 'with options set on Sequel::Database' do
        let(:service_name) { 'custom-sequel' }

        before do
          Datadog.configure { |c| c.tracing.instrument :sequel }
          Datadog.configure_onto(sequel, service_name: service_name)
          Datadog.configure { |c| c.tracing.instrument :sequel }
          perform_query!
        end

        it do
          expect(span.service).to eq(service_name)
        end

        it_behaves_like 'a peer service span'
      end

      context 'after the database has been initialized' do
        # NOTE: This test really only works when run in isolation.
        #       It relies on Sequel not being patched, and there's
        #       no way to unpatch it once its happened in other tests.
        before do
          sequel
          Datadog.configure { |c| c.tracing.instrument :sequel }
          perform_query!
        end

        it do
          expect(span.service).to eq('sqlite')
        end

        it_behaves_like 'a peer service span'
      end

      context 'when without service_name v0' do
        before do
          Datadog.configure { |c| c.tracing.instrument :sequel }
          perform_query!
        end

        it do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            expect(span.service).to eq('sqlite')
          end
        end
      end

      context 'when without service_name v1' do # default to include base
        before do
          Datadog.configure { |c| c.tracing.instrument :sequel }
          perform_query!
        end

        it do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            expect(span.service).to eq('rspec')
          end
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
