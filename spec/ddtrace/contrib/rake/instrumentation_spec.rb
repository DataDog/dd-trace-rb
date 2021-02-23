require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'securerandom'
require 'rake'
require 'rake/tasklib'
require 'ddtrace'
require 'ddtrace/contrib/rake/patcher'

RSpec.describe Datadog::Contrib::Rake::Instrumentation do
  let(:configuration_options) { { enabled: true } }
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

  before do
    skip('Rake integration incompatible.') unless Datadog::Contrib::Rake::Integration.compatible?

    # Reset options (that might linger from other tests)
    Datadog.configuration[:rake].reset!

    # Patch Rake
    Datadog.configure do |c|
      c.use :rake, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rake].reset_configuration!
    example.run
    Datadog.registry[:rake].reset_configuration!

    # We don't want instrumentation enabled during the rest of the test suite...
    Datadog.configure { |c| c.use :rake, enabled: false }
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

  describe '#invoke' do
    subject(:invoke) { task.invoke(*args) }

    before do
      ::Rake.application.instance_variable_set(:@top_level_tasks, [task_name.to_s])
      expect(tracer).to receive(:shutdown!).with(no_args).once.and_call_original
    end

    let(:invoke_span) { spans.find { |s| s.name == Datadog::Contrib::Rake::Ext::SPAN_INVOKE } }
    let(:execute_span) { spans.find { |s| s.name == Datadog::Contrib::Rake::Ext::SPAN_EXECUTE } }

    shared_examples_for 'a single task execution' do
      it 'contains invoke and execute spans' do
        expect(spans).to have(2).items
      end

      describe '\'rake.invoke\' span' do
        it do
          expect(invoke_span.name).to eq(Datadog::Contrib::Rake::Ext::SPAN_INVOKE)
          expect(invoke_span.resource).to eq(task_name.to_s)
          expect(invoke_span.parent_id).to eq(0)
        end

        it_behaves_like 'analytics for integration' do
          let(:span) { invoke_span }
          let(:analytics_enabled_var) { Datadog::Contrib::Rake::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Contrib::Rake::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'measured span for integration', true do
          let(:span) { invoke_span }
        end
      end

      describe '\'rake.execute\' span' do
        it do
          expect(execute_span.name).to eq(Datadog::Contrib::Rake::Ext::SPAN_EXECUTE)
          expect(execute_span.resource).to eq(task_name.to_s)
          expect(execute_span.parent_id).to eq(invoke_span.span_id)
          expect(execute_span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
        end
      end
    end

    shared_examples 'a successful single task execution' do
      before do
        expect(spy).to receive(:call) do |invocation_task, invocation_args|
          expect(invocation_task).to eq(task)
          expect(invocation_args.to_hash).to eq(args_hash)
        end
        expect(task).to receive(:shutdown_tracer!).with(no_args).twice.and_call_original
        invoke
      end

      it_behaves_like 'a single task execution' do
        describe '\'rake.invoke\' span' do
          it "has no error'" do
            expect(invoke_span).to_not have_error
          end
        end

        describe '\'rake.execute\' span' do
          it "has no error'" do
            expect(execute_span).to_not have_error
          end
        end
      end
    end

    shared_examples 'a failed single task execution' do
      before do
        expect(spy).to(receive(:call)) { raise error_class, 'oops' }
        expect(task).to receive(:shutdown_tracer!).with(no_args).twice.and_call_original
        expect { task.invoke(*args) }.to raise_error('oops')
      end

      let(:error_class) { Class.new(StandardError) }

      it_behaves_like 'a single task execution' do
        describe '\'rake.invoke\' span' do
          it 'has error' do
            expect(invoke_span).to have_error
            expect(invoke_span).to have_error_message('oops')
            expect(invoke_span).to have_error_type(error_class.to_s)
            expect(invoke_span).to have_error_stack
          end
        end

        describe '\'rake.execute\' span' do
          it 'has error' do
            expect(execute_span).to have_error
            expect(execute_span).to have_error_message('oops')
            expect(execute_span).to have_error_type(error_class.to_s)
            expect(execute_span).to have_error_stack
          end
        end
      end
    end

    context 'for a task' do
      let(:args_hash) { {} }
      let(:task_arg_names) { args_hash.keys }
      let(:args) { args_hash.values }

      let(:define_task!) do
        reset_task!(task_name)
        Rake::Task.define_task(task_name, *task_arg_names, &task_body)
      end

      before { define_task! }

      it 'returns task return value' do
        allow(spy).to receive(:call)
        expect(invoke).to contain_exactly(task_body)
      end

      context 'without args' do
        it_behaves_like 'a successful single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to eq([].to_s)
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_INVOKE_ARGS)).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq({}.to_s)
            end
          end
        end

        it_behaves_like 'a failed single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to eq([].to_s)
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_INVOKE_ARGS)).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq({}.to_s)
            end
          end
        end
      end

      context 'with args' do
        let(:args_hash) { { one: 1, two: 2, three: 3 } }

        it_behaves_like 'a successful single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to eq([:one, :two, :three].to_s)
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_INVOKE_ARGS)).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq(
                { one: '?', two: '?', three: '?' }.to_s
              )
            end
          end
        end
        it_behaves_like 'a failed single task execution' do
          describe '\'rake.invoke\' span tags' do
            it do
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to eq([:one, :two, :three].to_s)
              expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_INVOKE_ARGS)).to eq(['?'].to_s)
            end
          end

          describe '\'rake.execute\' span tags' do
            it do
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
              expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq(
                { one: '?', two: '?', three: '?' }.to_s
              )
            end
          end
        end
      end

      context 'with a prerequisite task' do
        let(:prerequisite_task_name) { :test_rake_instrumentation_prerequisite }
        let(:prerequisite_task_execute_span) do
          spans.find do |s|
            s.name == Datadog::Contrib::Rake::Ext::SPAN_EXECUTE \
            && s.resource == prerequisite_task_name.to_s
          end
        end
        let(:execute_span) do
          spans.find do |s|
            s.name == Datadog::Contrib::Rake::Ext::SPAN_EXECUTE \
            && s.resource == task_name.to_s
          end
        end
        let(:invoke_span) { spans.find { |s| s.name == Datadog::Contrib::Rake::Ext::SPAN_INVOKE } }
        let(:task_execute_span) do
          spans.find do |s|
            s.name == Datadog::Contrib::Rake::Ext::SPAN_EXECUTE \
            && s.resource == task_name.to_s
          end
        end
        let(:prerequisite_task_body) { proc { |task, args| prerequisite_spy.call(task, args) } }
        let(:prerequisite_spy) { double('prerequisite spy') }
        let(:prerequisite_task) { Rake::Task[prerequisite_task_name] }

        let(:define_task!) do
          reset_task!(task_name)
          reset_task!(prerequisite_task_name)
          Rake::Task.define_task(prerequisite_task_name, &prerequisite_task_body)
          Rake::Task.define_task(task_name => prerequisite_task_name, &task_body)
        end

        before do
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

          invoke
        end

        it 'contains invoke, execute, and prerequisite spans' do
          expect(spans).to have(3).items
        end

        describe '\'rake.invoke\' span' do
          it do
            expect(invoke_span.name).to eq(Datadog::Contrib::Rake::Ext::SPAN_INVOKE)
            expect(invoke_span.resource).to eq(task_name.to_s)
            expect(invoke_span.parent_id).to eq(0)
            expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to eq([].to_s)
            expect(invoke_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_INVOKE_ARGS)).to eq(['?'].to_s)
          end
        end

        describe 'prerequisite \'rake.execute\' span' do
          it do
            expect(prerequisite_task_execute_span.name).to eq(Datadog::Contrib::Rake::Ext::SPAN_EXECUTE)
            expect(prerequisite_task_execute_span.resource).to eq(prerequisite_task_name.to_s)
            expect(prerequisite_task_execute_span.parent_id).to eq(invoke_span.span_id)
            expect(prerequisite_task_execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
            expect(prerequisite_task_execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq({}.to_s)
          end
        end

        describe 'task \'rake.execute\' span' do
          it do
            expect(execute_span.name).to eq(Datadog::Contrib::Rake::Ext::SPAN_EXECUTE)
            expect(execute_span.resource).to eq(task_name.to_s)
            expect(execute_span.parent_id).to eq(invoke_span.span_id)
            expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_TASK_ARG_NAMES)).to be nil
            expect(execute_span.get_tag(Datadog::Contrib::Rake::Ext::TAG_EXECUTE_ARGS)).to eq({}.to_s)
          end
        end
      end

      context 'defined by a class' do
        let(:define_task!) do
          reset_task!(task_name)
          task_class.new(task_name, *task_arg_names)
        end

        it_behaves_like 'a successful single task execution'
        it_behaves_like 'a failed single task execution'
      end
    end
  end
end
