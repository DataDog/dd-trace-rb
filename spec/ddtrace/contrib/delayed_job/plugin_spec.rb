require 'spec_helper'
require 'ddtrace/contrib/delayed_job/plugin'

require_relative 'app'

SampleJob = Struct.new('SampleJob') { def perform; end }

RSpec.describe Datadog::Contrib::DelayedJob::Plugin do
  let(:writer) { FauxWriter.new }
  let(:tracer) { ::Datadog::Tracer.new(writer: writer) }
  let(:pin) { Datadog::Pin.get_from(::Delayed::Worker) }

  before do
    Datadog::Contrib::DelayedJob::Patcher.patch
    pin.tracer = tracer
  end

  describe 'running job' do
    let(:job_params) { {} }
    subject(:job_run) { Delayed::Job.enqueue(SampleJob.new, job_params) }

    before do
      Delayed::Worker.delay_jobs = false
    end

    it 'creates a span' do
      expect { job_run }.to change { writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    describe 'created span' do
      subject(:span) { writer.spans.first }

      before do
        job_run
      end

      it 'has service name taken from pin' do
        expect(span.service).to eq(pin.service)
      end

      it 'has resource name equal to job name' do
        expect(span.resource).to eq(SampleJob.name)
      end

      it "span tags doesn't include queue name" do
        expect(span.get_tag('delayed_job.queue')).to be_nil
      end

      it 'span tags include job id' do
        expect(span.get_tag('delayed_job.id')).not_to be_nil
      end

      it 'span tags include priority' do
        expect(span.get_tag('delayed_job.priority')).not_to be_nil
      end

      it 'span tags include number of attempts' do
        expect(span.get_tag('delayed_job.attempts')).to eq('0')
      end

      context 'when queue name is set' do
        let(:queue_name) { 'queue_name' }
        let(:job_params) { { queue: queue_name } }

        it 'span tags include queue name' do
          expect(span.get_tag('delayed_job.queue')).to eq(queue_name)
        end
      end

      context 'when job id is set' do
        let(:job_id) { 123456 }
        let(:job_params) { { id: job_id } }

        it 'span tags include job id' do
          expect(span.get_tag('delayed_job.id')).to eq(job_id.to_s)
        end
      end

      context 'when priority is set' do
        let(:priority) { 12345 }
        let(:job_params) { { priority: priority } }

        it 'span tags include job id' do
          expect(span.get_tag('delayed_job.priority')).to eq(priority.to_s)
        end
      end
    end
  end
end
