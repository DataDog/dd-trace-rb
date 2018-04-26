require 'spec_helper'

require 'securerandom'
require 'rake'
require 'rake/tasklib'
require 'ddtrace'
require 'ddtrace/contrib/rake/patcher'

RSpec.describe Datadog::Contrib::Rake::Instrumentation do
  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer, enabled: true } }
  let(:spans) { tracer.writer.spans }
  let(:span) { spans.first }

  before(:each) do
    skip('Rake integration incompatible.') unless Datadog::Contrib::Rake::Patcher.compatible?
    
    # Reset options (that might linger from other tests)
    Datadog.configuration[:rake].reset_options!

    # Patch Rake
    Datadog.configure do |c|
      c.use :rake, configuration_options
    end
  end

  after(:each) do
    # We don't want instrumentation enabled during the rest of the test suite...
    Datadog.configure do |c|
      c.use :rake, enabled: false
    end
  end

  def reset_task!(task_name)
    if Rake::Task.task_defined?(task_name)
      Rake::Task[task_name].reenable
      Rake::Task[task_name].clear
    end
  end

  let(:task_name) { :test_rake_instrumentation }
  let(:task_body) { Proc.new { |task, args| spy.call(task, args) } }
  let(:task_arg_names) { [] }
  let(:task_class) do
    stub_const('RakeInstrumentationTestTask', Class.new(Rake::TaskLib)).tap do |task_class|
      tb = task_body
      task_class.send(:define_method, :initialize) do |name = task_name, *args|
        task(name, *args, &tb)
      end
    end
  end
  let(:task) { Rake::Task[task_name] }
  let(:spy) { double('spy') }

  describe '#invoke' do
    shared_examples_for 'a single task execution' do
      before(:each) do
        expect(spy).to receive(:call) do |invocation_task, invocation_args|
          expect(invocation_task).to eq(task)
          expect(invocation_args.to_hash).to eq(args_hash)
        end
        task.invoke(*args)
      end

      let(:invoke_span) { spans.find { |s| s.name == described_class::SPAN_NAME_INVOKE } }
      let(:execute_span) { spans.find { |s| s.name == described_class::SPAN_NAME_EXECUTE } }

      it do
        expect(spans).to have(2).items
      end

      describe '\'rake.invoke\' span' do
        it do
          expect(invoke_span.name).to eq(described_class::SPAN_NAME_INVOKE)
          expect(invoke_span.resource).to eq(task_name.to_s)
          expect(invoke_span.parent_id).to eq(0)
        end
      end

      describe '\'rake.execute\' span' do
        it do
          expect(execute_span.name).to eq(described_class::SPAN_NAME_EXECUTE)
          expect(execute_span.resource).to eq(task_name.to_s)
          expect(execute_span.parent_id).to eq(invoke_span.span_id)
        end
      end
    end

    context 'for a task' do
      let(:args_hash) { {} }
      let(:task_arg_names) { args_hash.keys }
      let(:args) { args_hash.values }

      def define_task!
        reset_task!(task_name)
        Rake::Task.define_task(task_name, *task_arg_names, &task_body)
      end

      before(:each) { define_task! }

      context 'without args' do
        it_behaves_like 'a single task execution'
      end

      context 'with args' do
        let(:args_hash) { { one: 1, two: 2, three: 3 } }
        it_behaves_like 'a single task execution'
      end

      context 'with a prerequisite task' do
        let(:prerequisite_task_name) { :test_rake_instrumentation_prerequisite }
        let(:prerequisite_task_body) { Proc.new { |task, args| prerequisite_spy.call(task, args) } }
        let(:prerequisite_spy) { double('prerequisite spy') }
        let(:prerequisite_task) { Rake::Task[prerequisite_task_name] }

        def define_task!
          reset_task!(task_name)
          reset_task!(prerequisite_task_name)
          Rake::Task.define_task(prerequisite_task_name, &prerequisite_task_body)
          Rake::Task.define_task(task_name => prerequisite_task_name, &task_body)
        end

        before(:each) do
          expect(prerequisite_spy).to receive(:call) do |invocation_task, invocation_args|
            expect(invocation_task).to eq(prerequisite_task)
            expect(invocation_args.to_hash).to eq({})
          end.ordered

          expect(spy).to receive(:call) do |invocation_task, invocation_args|
            expect(invocation_task).to eq(task)
            expect(invocation_args.to_hash).to eq(args_hash)
          end.ordered

          task.invoke(*args)
        end

        let(:invoke_span) { spans.find { |s| s.name == described_class::SPAN_NAME_INVOKE } }
        let(:prerequisite_task_execute_span) do
          spans.find do |s|
            s.name == described_class::SPAN_NAME_EXECUTE \
            && s.resource == prerequisite_task_name.to_s
          end
        end
        let(:task_execute_span) do
          spans.find do |s|
            s.name == described_class::SPAN_NAME_EXECUTE \
            && s.resource == task_name.to_s
          end
        end

        it do
          expect(spans).to have(3).items
        end

        describe '\'rake.invoke\' span' do
          it do
            expect(invoke_span.name).to eq(described_class::SPAN_NAME_INVOKE)
            expect(invoke_span.resource).to eq(task_name.to_s)
            expect(invoke_span.parent_id).to eq(0)
          end
        end

        describe 'prerequisite \'rake.execute\' span' do
          it do
            expect(prerequisite_task_execute_span.name).to eq(described_class::SPAN_NAME_EXECUTE)
            expect(prerequisite_task_execute_span.resource).to eq(prerequisite_task_name.to_s)
            expect(prerequisite_task_execute_span.parent_id).to eq(invoke_span.span_id)
          end
        end

        describe 'task \'rake.execute\' span' do
          it do
            expect(task_execute_span.name).to eq(described_class::SPAN_NAME_EXECUTE)
            expect(task_execute_span.resource).to eq(task_name.to_s)
            expect(task_execute_span.parent_id).to eq(invoke_span.span_id)
          end
        end
      end

      context 'defined by a class' do
        def define_task!
          reset_task!(task_name)
          task_class.new(task_name, *task_arg_names)
        end

        it_behaves_like 'a single task execution'
      end
    end
  end
end
