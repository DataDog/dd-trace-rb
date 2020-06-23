require 'ddtrace/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'ClientTracerTest' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }
  let(:job_class) { EmptyWorker }

  before do
    Sidekiq.configure_client do |config|
      config.client_middleware.clear
      config.client_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::ClientTracer)
      end
    end

    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Extensions.enable_delay! if Sidekiq::VERSION > '5.0.0'
  end

  it 'traces job push' do
    perform_async

    expect(span.service).to eq('sidekiq-client')
    expect(span.resource).to eq('EmptyWorker')
    expect(span.get_tag('sidekiq.job.queue')).to eq('default')
    expect(span.status).to eq(0)
    expect(span.parent).to be_nil
    expect(span.get_metric('_dd.measured')).to be_nil
  end

  context 'with nested trace' do
    it 'traces job push' do
      tracer.trace('parent.span', service: 'parent-service') do
        perform_async
      end

      expect(spans).to have(2).items

      parent_span, child_span = spans

      expect(parent_span.name).to eq('parent.span')
      expect(parent_span.status).to eq(0)
      expect(parent_span.parent).to be_nil

      expect(child_span.service).to eq('sidekiq-client')
      expect(child_span.resource).to eq('EmptyWorker')
      expect(child_span.get_tag('sidekiq.job.queue')).to eq('default')
      expect(child_span.status).to eq(0)
      expect(child_span.parent).to eq(parent_span)
      expect(child_span.get_metric('_dd.measured')).to be_nil
    end
  end

  context 'with delayed extensions' do
    subject(:do_work) { DelayableClass.delay.do_work }

    before do
      stub_const('DelayableClass', Class.new do
        def self.do_work; end
      end)
    end

    it 'traces with correct resource' do
      do_work
      expect(spans.first.resource).to eq('DelayableClass.do_work')
    end
  end
end
