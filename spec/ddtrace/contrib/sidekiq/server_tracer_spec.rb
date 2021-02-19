require 'ddtrace/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Server tracer' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }

  let(:job_class) { EmptyWorker }

  before do
    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer)
    end

    Sidekiq::Extensions.enable_delay! if Sidekiq::VERSION > '5.0.0'
  end

  it 'traces async job run' do
    perform_async

    expect(spans).to have(2).items

    span, _push = spans
    expect(span.service).to eq('sidekiq')
    expect(span.resource).to eq('EmptyWorker')
    expect(span.get_tag('sidekiq.job.queue')).to eq('default')
    expect(span.get_tag('sidekiq.job.delay')).to_not be_nil
    expect(span.status).to eq(0)
    expect(span.parent).to be_nil
    expect(span.get_tag('sidekiq.job.args')).to be_nil
    expect(span.get_metric('_dd.measured')).to eq(1.0)
  end

  context 'with job run failing' do
    let(:job_class) { ErrorWorker }

    before do
      stub_const('ErrorWorker', Class.new do
        include Sidekiq::Worker

        def perform
          raise ZeroDivisionError, 'job error'
        end
      end)
    end

    it 'traces async job run' do
      expect { perform_async }.to raise_error(ZeroDivisionError)
      expect(spans).to have(2).items

      span, _push = spans
      expect(span.service).to eq('sidekiq')
      expect(span.resource).to eq('ErrorWorker')
      expect(span.get_tag('sidekiq.job.queue')).to eq('default')
      expect(span.get_tag('sidekiq.job.delay')).to_not be_nil
      expect(span.status).to eq(1)
      expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('job error')
      expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('ZeroDivisionError')
      expect(span.parent).to be_nil
      expect(span.get_tag('sidekiq.job.args')).to be_nil
      expect(span.get_metric('_dd.measured')).to eq(1.0)
    end
  end

  context 'with custom job' do
    before do
      stub_const('CustomWorker', Class.new do
        include Sidekiq::Worker

        def self.datadog_tracer_config
          { service_name: 'sidekiq-slow', tag_args: true }
        end

        def perform(_) end
      end)
    end

    it 'traces async job run' do
      perform_async
      CustomWorker.perform_async('random_id')

      expect(spans).to have(4).items

      custom, empty, _push, _push = spans

      expect(empty.service).to eq('sidekiq')
      expect(empty.resource).to eq('EmptyWorker')
      expect(empty.get_tag('sidekiq.job.queue')).to eq('default')
      expect(empty.get_tag('sidekiq.job.delay')).to_not be_nil
      expect(empty.status).to eq(0)
      expect(empty.parent).to be_nil
      expect(empty.get_metric('_dd.measured')).to eq(1.0)

      expect(custom.service).to eq('sidekiq-slow')
      expect(custom.resource).to eq('CustomWorker')
      expect(custom.get_tag('sidekiq.job.queue')).to eq('default')
      expect(custom.status).to eq(0)
      expect(custom.parent).to be_nil
      expect(custom.get_tag('sidekiq.job.args')).to eq(['random_id'].to_s)
      expect(custom.get_metric('_dd.measured')).to eq(1.0)
    end
  end

  context 'with delayed extensions' do
    subject(:do_work) { DelayableClass.delay.do_work }

    before do
      stub_const('DelayableClass', Class.new do
        def self.do_work
          puts 'a'
        end
      end)
    end

    it 'traces with correct resource' do
      do_work
      expect(spans.first.resource).to eq('DelayableClass.do_work')
    end
  end
end
