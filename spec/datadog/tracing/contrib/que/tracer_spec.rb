require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'ddtrace'
require 'que'

RSpec.describe Datadog::Tracing::Contrib::Que::Tracer do
  let(:job_options) do
    {
      queue: 'low',
      priority: 10,
      tags: { a: 1, b: 2 }
    }
  end
  let(:job_args) { { field_one: 1 } }
  let(:job_class) do
    stub_const(
      'TestJobClass',
      Class.new(::Que::Job) do
        def run(*args); end
      end
    )
  end
  let(:error_job_class) do
    stub_const(
      'ErrorJobClass',
      Class.new(::Que::Job) do
        def run(*_args)
          raise StandardError, 'with some error'
        end
      end
    )
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :que, configuration_options
    end

    Que::Job.run_synchronously = true
  end

  around do |example|
    Datadog.registry[:que].reset_configuration!
    example.run
    Datadog.registry[:que].reset_configuration!
  end

  describe '#call' do
    subject(:enqueue) { job_class.enqueue(job_args, job_options: job_options) }

    context 'with default options' do
      let(:configuration_options) { {} }

      it 'captures all generic span information' do
        enqueue

        expect(span.service).to eq(tracer.default_service)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('que')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_QUEUE)).to eq(job_options[:queue])
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_PRIORITY)).to eq(job_options[:priority])
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_ERROR_COUNT)).to eq(0)
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_EXPIRED_AT)).to eq('')
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_FINISHED_AT)).to eq('')
        expect(span.get_tag('messaging.system')).to eq('que')
      end

      it 'does not capture info for disabled tags' do
        enqueue

        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_ARGS)).to eq(nil)
        expect(span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_DATA)).to eq(nil)
      end

      it 'continues to capture spans gracefully under unexpected conditions' do
        expect { error_job_class.enqueue(**job_args) }.to raise_error(StandardError)
        expect(spans).not_to be_empty
        expect(span.start_time).not_to be_nil
        expect(span.end_time).not_to be_nil
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to eq('StandardError')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).not_to be_nil
        expect(span.get_tag('messaging.system')).to eq('que')
      end

      it 'has span.kind tag with value consumer' do
        enqueue

        expect(span.get_tag('span.kind')).to eq('consumer')
      end
    end

    context 'with tag_args enabled' do
      let(:configuration_options) { { tag_args: true } }

      it 'captures span info for args tag' do
        enqueue

        actual_span_value   = span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_ARGS)
        expected_span_value = [{ field_one: 1 }].to_s

        expect(actual_span_value).to eq(expected_span_value)
      end
    end

    context 'with tag_data enabled' do
      let(:configuration_options) { { tag_data: true } }

      it 'captures spans info for data tag' do
        enqueue

        actual_span_value   = span.get_tag(Datadog::Tracing::Contrib::Que::Ext::TAG_JOB_DATA)
        expected_span_value = { tags: job_options[:tags] }.to_s

        expect(actual_span_value).to eq(expected_span_value)
      end
    end
  end
end
