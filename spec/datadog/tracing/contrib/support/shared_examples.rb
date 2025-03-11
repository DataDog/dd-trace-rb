RSpec.shared_examples 'a contrib integration' do |datadog_dependency: false|
  described_class.gems.each do |gem|
    context "when loading the #{gem} gem" do
      let(:registered_integration) { Datadog.registry[integration.name] }

      before do
        if datadog_dependency
          skip "The gem #{gem} is a datadog dependency and will always be loaded when the tracer starts"
        end

        expect(registered_integration.patcher.patch_successful).to be_falsey,
                                                        "This test can only run if the integration :#{integration.name} has not patched the environment"
        expect($LOADED_FEATURES.find { |x| x.end_with?("/lib/#{gem}.rb") }).to be_nil,
                                                                 "This test can only run if the gem '#{gem}' is not loaded"
      end

      it 'patches the integration on require' do
        # Fork so we don't pollute the current test environment
        expect_in_fork do
          Datadog.configure { |c| c.tracing.instrument integration.name }

          expect { require gem }.to change { integration.patcher.patch_successful }.from(be_falsey).to(be_truthy)
        end
      end
    end
  end
end
