require('helper')
require('sucker_punch')
require('ddtrace')
require_relative('dummy_worker')
module Datadog
  module Contrib
    module SuckerPunch
      class PatcherTest < Minitest::Test
        before do
          Datadog.configure { |c| c.use(:sucker_punch) }
          ::SuckerPunch::Queue.clear
          ::SuckerPunch::RUNNING.make_true
          @tracer = enable_test_tracer!
        end
        it('two spans per job') do
          ::DummyWorker.perform_async
          try_wait_until { (all_spans.length == 2) }
          expect(all_spans.length).to(eq(2))
        end
        it('successful job') do
          ::DummyWorker.perform_async
          try_wait_until { (all_spans.length == 2) }
          span = all_spans.find { |s| s.resource[/PROCESS/] }
          expect(span.service).to(eq('sucker_punch'))
          expect(span.name).to(eq('sucker_punch.perform'))
          expect(span.resource).to(eq('PROCESS DummyWorker'))
          expect(span.get_tag('sucker_punch.queue')).to(eq('DummyWorker'))
          expect(span.status).to_not(eq(Ext::Errors::STATUS))
        end
        it('failed job') do
          ::DummyWorker.perform_async(:fail)
          try_wait_until { (all_spans.length == 2) }
          span = all_spans.find { |s| s.resource[/PROCESS/] }
          expect(span.service).to(eq('sucker_punch'))
          expect(span.name).to(eq('sucker_punch.perform'))
          expect(span.resource).to(eq('PROCESS DummyWorker'))
          expect(span.get_tag('sucker_punch.queue')).to(eq('DummyWorker'))
          expect(span.status).to(eq(Ext::Errors::STATUS))
          expect(span.get_tag(Ext::Errors::TYPE)).to(eq('ZeroDivisionError'))
          expect(span.get_tag(Ext::Errors::MSG)).to(eq('divided by 0'))
        end
        it('async enqueueing') do
          ::DummyWorker.perform_async
          try_wait_until { all_spans.any? }
          span = all_spans.find { |s| s.resource[/ENQUEUE/] }
          expect(span.service).to(eq('sucker_punch'))
          expect(span.name).to(eq('sucker_punch.perform_async'))
          expect(span.resource).to(eq('ENQUEUE DummyWorker'))
          expect(span.get_tag('sucker_punch.queue')).to(eq('DummyWorker'))
        end
        it('delayed enqueueing') do
          ::DummyWorker.perform_in(0)
          try_wait_until { all_spans.any? }
          span = all_spans.find { |s| s.resource[/ENQUEUE/] }
          expect(span.service).to(eq('sucker_punch'))
          expect(span.name).to(eq('sucker_punch.perform_in'))
          expect(span.resource).to(eq('ENQUEUE DummyWorker'))
          expect(span.get_tag('sucker_punch.queue')).to(eq('DummyWorker'))
          expect(span.get_tag('sucker_punch.perform_in')).to(eq('0'))
        end

        private

        attr_reader(:tracer)
        def all_spans
          tracer.writer.spans(:keep)
        end

        def enable_test_tracer!
          get_test_tracer.tap { |tracer| pin.tracer = tracer }
        end

        def pin
          ::SuckerPunch.datadog_pin
        end
      end
    end
  end
end
