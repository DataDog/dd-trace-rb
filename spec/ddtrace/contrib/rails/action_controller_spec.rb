require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'ActionController tracing' do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:rails_options) { { tracer: tracer } }

  before(:each) do
    Datadog::RailsActionPatcher.patch_action_controller
    Datadog.configure do |c|
      c.use :rails, rails_options
    end
  end

  def all_spans
    tracer.writer.spans(:keep)
  end

  let(:controller) do
    stub_const('TestController', Class.new(base_class) do
      def index
        # Do nothing
      end
    end)
  end
  let(:name) { :index }
  let(:base_class) { ActionController::Base }

  describe '#action' do
    subject(:result) { action.call(env) }
    let(:action) { controller.action(name) }
    let(:env) { {} }

    shared_examples_for 'a successful dispatch' do
      it do
        expect { result }.to_not raise_error
        expect(result).to be_a_kind_of(Array)
        expect(result).to have(3).items
        expect(all_spans).to have(1).items
        expect(all_spans.first.name).to eq('rails.action_controller')
      end
    end

    describe 'for a controller' do
      context 'that inherits from ActionController::Metal' do
        let(:base_class) { ActionController::Metal }

        before(:each) do
          # ActionController::Metal is only patched in 2.0+
          skip 'Not supported for Ruby < 2.0' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
        end

        it_behaves_like 'a successful dispatch'

        context 'when response is overridden' do
          context 'with an Array' do
            let(:headers) { double('headers') }
            let(:body) { double('body') }

            before(:each) do
              expect_any_instance_of(controller).to receive(:response)
                .at_least(:once)
                .and_wrap_original do |m, *args|
                  m.receiver.response = [200, headers, body]
                  m.call(*args)
                end
            end

            it do
              expect { result }.to_not raise_error
              expect(result).to be_a_kind_of(Array)
              expect(result).to include(200, headers, body)
              expect(all_spans).to have(1).items
              expect(all_spans.first.name).to eq('rails.action_controller')
            end
          end
        end
      end
    end
  end
end
