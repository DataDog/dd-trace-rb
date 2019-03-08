require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails trace analytics' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before(:each) do
    Datadog::RailsActionPatcher.patch_action_controller
    Datadog.configure do |c|
      c.use :rails, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rails].reset_configuration!
    example.run
    Datadog.registry[:rails].reset_configuration!
  end

  let(:span) { spans.first }
  let(:spans) { tracer.writer.spans(:keep) }

  describe 'for a controller action' do
    subject(:result) { action.call(env) }
    let(:controller) do
      stub_const('TestController', Class.new(base_class) do
        def index
          # Do nothing
        end
      end)
    end
    let(:name) { :index }
    let(:base_class) { ActionController::Metal }
    let(:action) { controller.action(name) }
    let(:env) { {} }

    before(:each) do
      # ActionController::Metal is only patched in 2.0+
      skip 'Not supported for Ruby < 2.0' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
    end

    shared_examples_for 'a successful dispatch' do
      it do
        expect { result }.to_not raise_error
        expect(result).to be_a_kind_of(Array)
        expect(result).to have(3).items
        expect(spans).to have(1).items
        expect(span.name).to eq('rails.action_controller')
      end
    end

    it_behaves_like 'analytics for integration' do
      before { expect { result }.to_not raise_error }
      let(:analytics_enabled_var) { Datadog::Contrib::Rails::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Rails::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      it_behaves_like 'a successful dispatch'
    end
  end
end
