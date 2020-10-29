require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'active_record'
require 'delayed_job'
require 'delayed_job_active_record'
require 'ddtrace'
require 'ddtrace/contrib/delayed_job/plugin'
require_relative 'delayed_job_active_record'

RSpec.describe Datadog::Contrib::DelayedJob::Plugin, :delayed_job_active_record do
  let(:sample_job_object) do
    stub_const('SampleJob', Class.new do
      def perform; end
    end)
  end
  let(:active_job_sample_job_object) do
    stub_const('ActiveJobSampleJob', Class.new do
      def perform; end

      def job_data
        {
          'job_class' => 'UnderlyingJobClass'
        }
      end
    end)
  end

  let(:configuration_options) { {} }

  before do
    Datadog.configure { |c| c.use :delayed_job, configuration_options }
    Delayed::Worker.delay_jobs = false
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:delayed_job].reset_configuration!
    example.run
    Datadog.registry[:delayed_job].reset_configuration!
  end

  describe 'instrumenting worker execution' do
    let(:worker) { double(:worker, name: 'worker') }
    before do
      allow(tracer).to receive(:shutdown!).and_call_original
    end

    it 'execution callback yields control' do
      expect { |b| Delayed::Worker.lifecycle.run_callbacks(:execute, worker, &b) }.to yield_with_args(worker)
    end

    it 'shutdown happens after yielding' do
      Delayed::Worker.lifecycle.run_callbacks(:execute, worker) do
        expect(tracer).not_to have_received(:shutdown!)
      end

      expect(tracer).to have_received(:shutdown!)
    end
  end

  describe 'instrumented job invocation' do
    let(:job_params) { {} }
    let(:span) { fetch_spans.first }
    let(:enqueue_span) { fetch_spans.first }

    subject(:job_run) { Delayed::Job.enqueue(sample_job_object.new, job_params) }

    it 'creates a span' do
      expect { job_run }.to change { fetch_spans }.to all(be_instance_of(Datadog::Span))
    end

    context 'when the job looks like Active Job' do
      subject(:job_run) { Delayed::Job.enqueue(active_job_sample_job_object.new, job_params) }

      before { job_run }

      it 'has resource name equal to underlying ActiveJob class name' do
        expect(span.resource).to eq('UnderlyingJobClass')
        expect(enqueue_span.resource).to eq('UnderlyingJobClass')
      end
    end

    context 'when job fails' do
      let(:configuration_options) { { error_handler: error_handler } }
      let(:error_handler) { proc {} }

      let(:sample_job_object) do
        stub_const('SampleJob', Class.new do
          def perform
            raise ZeroDivisionError, 'job error'
          end
        end)
      end

      it 'uses custom error handler' do
        expect(error_handler).to receive(:call)
        expect { job_run }.to raise_error
      end
    end

    shared_context 'delayed_job common tags and resource' do
      it 'has resource name equal to job name' do
        expect(span.resource).to eq('SampleJob')
      end

      it "span tags doesn't include queue name" do
        expect(span.get_tag('delayed_job.queue')).to be_nil
      end

      it 'span tags include priority' do
        expect(span.get_tag('delayed_job.priority')).not_to be_nil
      end

      it "span tags doesn't include queue name" do
        expect(span.get_tag('delayed_job.queue')).to be_nil
      end

      context 'when queue name is set' do
        let(:queue_name) { 'queue_name' }
        let(:job_params) { { queue: queue_name } }

        it 'span tags include queue name' do
          expect(span.get_tag('delayed_job.queue')).to eq(queue_name)
        end
      end

      it 'span tags include priority' do
        expect(span.get_tag('delayed_job.priority')).not_to be_nil
      end

      context 'when priority is set' do
        let(:priority) { 12345 }
        let(:job_params) { { priority: priority } }

        it 'span tags include priority' do
          expect(span.get_tag('delayed_job.priority')).to eq(priority)
        end
      end
    end

    describe 'invoke span' do
      subject(:span) { fetch_spans.first }
      before { job_run }

      include_context 'delayed_job common tags and resource'

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::DelayedJob::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::DelayedJob::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true

      it 'has service name taken from configuration' do
        expect(span.service).not_to be_nil
        expect(span.service).to eq(Datadog.configuration[:delayed_job][:service_name])
      end

      it 'span tags include job id' do
        expect(span.get_tag('delayed_job.id')).not_to be_nil
      end

      it 'span tags include number of attempts' do
        expect(span.get_tag('delayed_job.attempts')).to eq(0)
      end
    end

    describe 'enqueue span' do
      subject(:span) { fetch_spans.last }
      before { job_run }

      include_context 'delayed_job common tags and resource'

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::DelayedJob::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::DelayedJob::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true

      it 'has service name taken from configuration' do
        expect(span.service).not_to be_nil
        expect(span.service).to eq(Datadog.configuration[:delayed_job][:client_service_name])
      end
    end
  end
end
