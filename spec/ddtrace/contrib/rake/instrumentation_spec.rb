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

      # Rake prior to version 12.0 doesn't clear args when #clear is invoked.
      # Perform a more invasive reset, to make sure its reusable.
      if Gem::Version.new(Rake::VERSION) < Gem::Version.new('12.0')
        Rake::Task[task_name].instance_variable_set(:@arg_names, nil)
      end
    end
  end

  let(:task_name) { :test_rake_instrumentation }
  let(:task_body) { proc { |task, args| spy.call(task, args) } }
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
    before(:each) do
      ::Rake.application.instance_variable_set(:@top_level_tasks, [task_name.to_s])
      expect(tracer).to receive(:shutdown!).with(no_args).once.and_call_original
    end

    shared_examples_for 'a single task execution' do
      before(:each) do
        expect(spy).to receive(:call) do |invocation_task, invocation_args|
          expect(invocation_task).to eq(task)
          expect(invocation_args.to_hash).to eq(args_hash)
        end
        expect(task).to receive(:shutdown_tracer!).with(no_args).twice.and_call_original
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

    shared_examples 'an error occurrence' do
      before(:each) do
        expect(spy).to receive(:call) do
          raise 'oops'
        end
        expect(task).to receive(:shutdown_tracer!).with(no_args).twice.and_call_original
      end
      it { expect { task.invoke(*args) }.to raise_error('oops') }
    end

    context 'for a task' do
      let(:args_hash) { {} }
      let(:task_arg_names) { args_hash.keys }
      let(:args) { args_hash.values }

      let(:define_task!) do
        reset_task!(task_name)
        Rake::Task.define_task(task_name, *task_arg_names, &task_body)
      end

      before(:each) { define_task! }

      context 'without args' do
        it_behaves_like 'a single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag('rake.task.arg_names')).to eq([].to_s)
              expect(invoke_span.get_tag('rake.invoke.args')).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag('rake.task.arg_names')).to be nil
              expect(execute_span.get_tag('rake.execute.args')).to eq({}.to_s)
            end
          end
        end
        it_behaves_like 'an error occurrence'
      end

      context 'with args' do
        let(:args_hash) { { one: 1, two: 2, three: 3 } }
        it_behaves_like 'a single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag('rake.task.arg_names')).to eq([:one, :two, :three].to_s)
              expect(invoke_span.get_tag('rake.invoke.args')).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag('rake.arg_names')).to be nil
              expect(execute_span.get_tag('rake.execute.args')).to eq({ one: '?', two: '?', three: '?' }.to_s)
            end
          end
        end
        it_behaves_like 'an error occurrence'
      end

      context 'with a prerequisite task' do
        let(:prerequisite_task_name) { :test_rake_instrumentation_prerequisite }
        let(:prerequisite_task_body) { proc { |task, args| prerequisite_spy.call(task, args) } }
        let(:prerequisite_spy) { double('prerequisite spy') }
        let(:prerequisite_task) { Rake::Task[prerequisite_task_name] }

        let(:define_task!) do
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

          expect(task).to receive(:shutdown_tracer!).with(no_args).twice.and_call_original
          expect(prerequisite_task).to receive(:shutdown_tracer!).with(no_args).once.and_call_original

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
            expect(invoke_span.get_tag('rake.task.arg_names')).to eq([].to_s)
            expect(invoke_span.get_tag('rake.invoke.args')).to eq(['?'].to_s)
          end
        end

        describe 'prerequisite \'rake.execute\' span' do
          it do
            expect(prerequisite_task_execute_span.name).to eq(described_class::SPAN_NAME_EXECUTE)
            expect(prerequisite_task_execute_span.resource).to eq(prerequisite_task_name.to_s)
            expect(prerequisite_task_execute_span.parent_id).to eq(invoke_span.span_id)
            expect(prerequisite_task_execute_span.get_tag('rake.task.arg_names')).to be nil
            expect(prerequisite_task_execute_span.get_tag('rake.execute.args')).to eq({}.to_s)
          end
        end

        describe 'task \'rake.execute\' span' do
          it do
            expect(task_execute_span.name).to eq(described_class::SPAN_NAME_EXECUTE)
            expect(task_execute_span.resource).to eq(task_name.to_s)
            expect(task_execute_span.parent_id).to eq(invoke_span.span_id)
            expect(task_execute_span.get_tag('rake.task.arg_names')).to be nil
            expect(task_execute_span.get_tag('rake.execute.args')).to eq({}.to_s)
          end
        end
      end

      context 'defined by a class' do
        let(:define_task!) do
          reset_task!(task_name)
          task_class.new(task_name, *task_arg_names)
        end

        it_behaves_like 'a single task execution'
        it_behaves_like 'an error occurrence'
      end
    end
  end
end
