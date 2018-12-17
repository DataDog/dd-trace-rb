require 'spec_helper'
require 'ddtrace'

require 'active_record'
require 'sqlite3'

RSpec.describe 'ActiveRecord tracing performance' do
  let(:tracer) { get_test_tracer }
  let(:options) { { tracer: tracer } }
  let(:spans) { tracer.writer.spans }

  before(:each) do
    skip('Performance test does not run in CI.')

    # Configure the tracer
    Datadog.configure do |c|
      c.use :active_record, options
    end
  end

  after(:each) { Datadog.registry[:active_record].reset_configuration! }

  describe 'for an in-memory database' do
    let!(:connection) do
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    end

    describe 'when queried with a simple select' do
      subject(:measurement) { measure(iterations) }
      let(:iterations) { 100_000 }

      def measure(iterations = 1)
        Benchmark.measure do
          iterations.times do
            connection.connection.execute('SELECT 42')
          end
        end
      end

      before(:each) do
        # Perform a measurement to warm up
        measure(10)

        # Discard warm-up spans
        tracer.writer.spans
      end

      it 'produces a measurement' do
        expect { measurement }.to_not raise_error
        expect(spans).to have(iterations).items
        puts "\nRun time for #{iterations} iterations: #{measurement.utime}\n"
      end
    end
  end
end
