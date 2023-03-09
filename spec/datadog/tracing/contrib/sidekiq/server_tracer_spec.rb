require 'datadog/tracing/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Server tracer' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }

  let(:job_class) { EmptyWorker }
  let(:sidekiq_options) { {} }

  before do
    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Tracing::Contrib::Sidekiq::ServerTracer)
    end

    Sidekiq::Extensions.enable_delay! if Sidekiq::VERSION > '5.0.0'
  end

  it 'traces async job run' do
    perform_async

    expect(spans).to have(2).items

    span, _push = spans
    expect(span.service).to eq(tracer.default_service)
    expect(span.resource).to eq('EmptyWorker')
    expect(span.get_tag('sidekiq.job.queue')).to eq('default')
    expect(span.get_tag('sidekiq.job.delay')).to_not be_nil
    expect(span.status).to eq(0)
    expect(span).to be_root_span
    expect(span.get_tag('sidekiq.job.args')).to be_nil
    expect(span.get_metric('_dd.measured')).to eq(1.0)
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job')
    expect(span.get_tag('span.kind')).to eq('consumer')
    expect(span.get_tag('messaging.system')).to eq('sidekiq')
  end

  context 'with job run failing' do
    let(:job_class) { ErrorWorker }

    before do
      stub_const(
        'ErrorWorker',
        Class.new do
          include Sidekiq::Worker

          def perform
            raise ZeroDivisionError, 'job error'
          end
        end
      )
    end

    it 'traces async job run' do
      expect { perform_async }.to raise_error(ZeroDivisionError)
      expect(spans).to have(2).items

      span, _push = spans
      expect(span.service).to eq(tracer.default_service)
      expect(span.resource).to eq('ErrorWorker')
      expect(span.get_tag('sidekiq.job.queue')).to eq('default')
      expect(span.get_tag('sidekiq.job.delay')).to_not be_nil
      expect(span.status).to eq(1)
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)).to eq('job error')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to eq('ZeroDivisionError')
      expect(span).to be_root_span
      expect(span.get_tag('sidekiq.job.args')).to be_nil
      expect(span.get_metric('_dd.measured')).to eq(1.0)
      expect(span.get_tag('span.kind')).to eq('consumer')
      expect(span.get_tag('messaging.system')).to eq('sidekiq')
    end
  end

  context 'with custom job' do
    before do
      allow(Datadog.configuration.tracing).to receive(:[]).with(:sidekiq).and_return(sidekiq_options)

      stub_const(
        'CustomWorker',
        Class.new do
          include Sidekiq::Worker

          def perform(id) end
        end
      )
    end

    it 'traces async job run' do
      perform_async
      CustomWorker.perform_async('random_id')

      expect(spans).to have(4).items

      custom, empty, _push, _push = spans

      expect(empty.service).to eq(tracer.default_service)
      expect(empty.resource).to eq('EmptyWorker')
      expect(empty.get_tag('sidekiq.job.queue')).to eq('default')
      expect(empty.get_tag('sidekiq.job.delay')).to_not be_nil
      expect(empty.status).to eq(0)
      expect(empty).to be_root_span
      expect(empty.get_metric('_dd.measured')).to eq(1.0)
      expect(empty.get_tag('span.kind')).to eq('consumer')

      expect(custom.service).to eq(tracer.default_service)
      expect(custom.resource).to eq('CustomWorker')
      expect(custom.get_tag('sidekiq.job.queue')).to eq('default')
      expect(custom.status).to eq(0)
      expect(custom).to be_root_span
      expect(custom.get_tag('sidekiq.job.args')).to eq(['?'].to_s)
      expect(custom.get_metric('_dd.measured')).to eq(1.0)
      expect(custom.get_tag('span.kind')).to eq('consumer')
      expect(custom.get_tag('messaging.system')).to eq('sidekiq')
    end

    context 'with tag_args' do
      let(:sidekiq_options) { { service_name: 'sidekiq-slow', tag_args: true } }

      it 'records tag values' do
        perform_async
        CustomWorker.perform_async('random_id')

        expect(spans).to have(4).items

        custom, _empty, _push, _push = spans

        expect(custom.get_tag('sidekiq.job.args')).to eq(['random_id'].to_s)
      end
    end

    context 'with default quantization' do
      let(:sidekiq_options) { { service_name: 'sidekiq-slow', quantize: {} } }

      it 'hides tag values' do
        perform_async
        CustomWorker.perform_async('random_id')

        expect(spans).to have(4).items

        custom, _empty, _push, _push = spans

        expect(custom.get_tag('sidekiq.job.args')).to eq(['?'].to_s)
      end
    end

    context 'with quantization showing all' do
      let(:sidekiq_options) { { service_name: 'sidekiq-slow', quantize: { args: { show: :all } } } }

      it 'records tag values' do
        perform_async
        CustomWorker.perform_async('random_id')

        expect(spans).to have(4).items

        custom, empty, _push, _push = spans

        expect(empty.resource).to eq('EmptyWorker')
        expect(empty.get_tag('sidekiq.job.queue')).to eq('default')
        expect(empty.get_tag('sidekiq.job.delay')).to_not be_nil
        expect(empty.status).to eq(0)
        expect(empty).to be_root_span
        expect(empty.get_metric('_dd.measured')).to eq(1.0)
        expect(empty.get_tag('span.kind')).to eq('consumer')
        expect(empty.get_tag('messaging.system')).to eq('sidekiq')

        expect(custom.service).to eq('sidekiq-slow')
        expect(custom.resource).to eq('CustomWorker')
        expect(custom.get_tag('sidekiq.job.queue')).to eq('default')
        expect(custom.status).to eq(0)
        expect(custom).to be_root_span
        expect(custom.get_tag('sidekiq.job.args')).to eq(['random_id'].to_s)
        expect(custom.get_metric('_dd.measured')).to eq(1.0)
        expect(custom.get_tag('span.kind')).to eq('consumer')
        expect(custom.get_tag('messaging.system')).to eq('sidekiq')
      end
    end
  end

  context 'with delayed extensions' do
    subject(:do_work) { DelayableClass.delay.do_work }

    before do
      if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1.0')
        pending 'Broken in Ruby 3.1.0-preview1, see https://github.com/mperham/sidekiq/issues/5064'
      end

      stub_const(
        'DelayableClass',
        Class.new do
          def self.do_work
            puts 'a'
          end
        end
      )
    end

    it 'traces with correct resource' do
      do_work
      expect(spans.first.resource).to eq('DelayableClass.do_work')
    end
  end
end
