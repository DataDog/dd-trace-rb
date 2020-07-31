require 'ddtrace/contrib/support/spec_helper'
require 'sucker_punch'
require 'ddtrace'
require_relative 'dummy_worker'

RSpec.describe 'Sinatra instrumentation' do
  before do
    Datadog.configure do |c|
      c.use :sucker_punch
    end

    ::SuckerPunch::Queue.clear
    ::SuckerPunch::RUNNING.make_true
  end

  after do
    ::SuckerPunch::Queue.clear
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:sucker_punch].reset_configuration!
    example.run
    Datadog.registry[:sucker_punch].reset_configuration!
  end

  context 'successful job' do
    subject(:dummy_work_success) { ::DummyWorker.perform_async }

    it 'should generate two spans, one for pushing to enqueue and one for the job itself' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }
      expect(spans.length).to eq(2)
    end

    it 'should instrument successful job' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      span = spans.find { |s| s.resource[/PROCESS/] }

      expect('sucker_punch').to eq(span.service)
      expect('sucker_punch.perform').to eq(span.name)
      expect('PROCESS DummyWorker').to eq(span.resource)
      expect('DummyWorker').to eq(span.get_tag('sucker_punch.queue'))
      expect(Datadog::Ext::Errors::STATUS).not_to eq(span.status)
      expect(span.get_metric('_dd.measured')).to eq(1.0)
    end

    it 'should instrument successful enqueuing' do
      is_expected.to be true
      try_wait_until { fetch_spans.any? }

      span = spans.find { |s| s.resource[/ENQUEUE/] }

      expect('sucker_punch').to eq(span.service)
      expect('sucker_punch.perform_async').to eq(span.name)
      expect('ENQUEUE DummyWorker').to eq(span.resource)
      expect('DummyWorker').to eq(span.get_tag('sucker_punch.queue'))
      expect(span.get_metric('_dd.measured')).to eq(1.0)
    end
  end

  context 'failed job' do
    subject(:dummy_work_fail) { ::DummyWorker.perform_async(:fail) }

    it 'should instrument a failed job' do
      is_expected.to be true
      try_wait_until { fetch_spans.length == 2 }

      span = spans.find { |s| s.resource[/PROCESS/] }

      expect('sucker_punch').to eq(span.service)
      expect('sucker_punch.perform').to eq(span.name)
      expect('PROCESS DummyWorker').to eq(span.resource)
      expect('DummyWorker').to eq(span.get_tag('sucker_punch.queue'))
      expect(Datadog::Ext::Errors::STATUS).to eq(span.status)
      expect('ZeroDivisionError').to eq(span.get_tag(Datadog::Ext::Errors::TYPE))
      expect('divided by 0').to eq(span.get_tag(Datadog::Ext::Errors::MSG))
      expect(span.get_metric('_dd.measured')).to eq(1.0)
    end
  end

  context 'delayed job' do
    subject(:dummy_worker_delay) { ::DummyWorker.perform_in(0) }

    it 'should instrument enqueuing for a delayed job' do
      is_expected.to be true
      try_wait_until { fetch_spans.any? }

      span = spans.find { |s| s.resource[/ENQUEUE/] }

      expect('sucker_punch').to eq(span.service)
      expect('sucker_punch.perform_in').to eq(span.name)
      expect('ENQUEUE DummyWorker').to eq(span.resource)
      expect('DummyWorker').to eq(span.get_tag('sucker_punch.queue'))
      expect(0).to eq(span.get_tag('sucker_punch.perform_in'))
      expect(span.get_metric('_dd.measured')).to eq(1.0)
    end
  end
end
