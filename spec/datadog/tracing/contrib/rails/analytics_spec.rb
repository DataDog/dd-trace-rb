require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails trace analytics' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rails, configuration_options
      # Manually activate ActionPack to trigger patching.
      # This is because Rails instrumentation normally defers patching until #after_initialize
      # when it activates and configures each of the Rails components with application details.
      # We aren't initializing a full Rails application here, so the patch doesn't auto-apply.
      c.tracing.instrument :action_pack, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rails].reset_configuration!
    Datadog.registry[:action_pack].reset_configuration!
    example.run
    Datadog.registry[:rails].reset_configuration!
    Datadog.registry[:action_pack].reset_configuration!
  end

  describe 'for a controller action' do
    subject(:result) { action.call(env) }

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
    let(:base_class) { ActionController::Metal }
    let(:action) { controller.action(name) }
    let(:env) { {} }

    shared_examples_for 'a successful dispatch' do
      it do
        expect { result }.to_not raise_error
        expect(result).to be_a_kind_of(Array)
        expect(result).to have(3).items
        expect(spans).to have(1).items
        expect(span.name).to eq('rails.action_controller')
      end
    end

    it_behaves_like 'analytics for integration', ignore_global_flag: false do
      before { expect { result }.to_not raise_error }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Rails::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      it_behaves_like 'a successful dispatch'
    end
  end
end
