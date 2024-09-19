require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails ActionController' do
  let(:rails_options) { {} }
  let(:controller) do
    stub_const(
      'TestController',
      Class.new(base_class) do
        def index
          # Do nothing
        end
      end
    )
  end
  let(:name) { :index }
  let(:base_class) { ActionController::Base }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails, rails_options
      # Manually activate ActionPack to trigger patching.
      # This is because Rails instrumentation normally defers patching until #after_initialize
      # when it activates and configures each of the Rails components with application details.
      # We aren't initializing a full Rails application here, so the patch doesn't auto-apply.
      c.tracing.instrument :action_pack
    end
  end

  describe '#action' do
    subject(:result) { action.call(env) }

    let(:action) { controller.action(name) }
    let(:env) { {} }

    describe 'for a controller' do
      context 'that inherits from ActionController::Metal' do
        let(:base_class) { ActionController::Metal }

        it do
          expect { result }.to_not raise_error
          expect(result).to be_a_kind_of(Array)
          expect(result).to have(3).items
          expect(spans).to have(1).items
          expect(spans.first.name).to eq('rails.action_controller')
        end

        context 'with tracing disabled' do
          before do
            Datadog.configure { |c| c.tracing.enabled = false }
            expect(Datadog.logger).to_not receive(:error)
            expect(Datadog::Tracing).to_not receive(:trace)
          end

          it 'runs the action without tracing' do
            expect { result }.to_not raise_error
            expect(spans).to have(0).items
          end
        end

        context 'when response is overridden' do
          context 'with an Array' do
            let(:headers) { double('headers') }
            let(:body) { double('body') }

            before do
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
              expect(spans).to have(1).items
              expect(spans.first.name).to eq('rails.action_controller')
            end
          end

          context 'with some unknown kind of object' do
            let(:response_object) do
              double(
                'response object',
                to_a: [200, double('headers'), double('body')]
              )
            end

            before do
              expect_any_instance_of(controller).to receive(:response)
                .at_least(:once)
                .and_wrap_original do |m, *args|
                  m.receiver.response = response_object
                  m.call(*args)
                end
            end

            it do
              expect { result }.to_not raise_error
              expect(result).to be_a_kind_of(Array)
              expect(result).to have(3).items
              expect(spans).to have(1).items
              expect(spans.first.name).to eq('rails.action_controller')
            end
          end
        end

        describe 'span resource' do
          let(:observed) { {} }
          let(:controller) do
            observed = self.observed
            stub_const(
              'TestController',
              Class.new(base_class) do
                define_method(:index) do
                  observed[:active_span_resource] = Datadog::Tracing.active_span.resource
                end
              end
            )
          end

          it 'sets the span resource before calling the controller' do
            result

            expect(observed[:active_span_resource]).to eq 'TestController#index'
          end
        end
      end
    end
  end
end
