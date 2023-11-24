RSpec.shared_examples 'a contrib integration' do
  described_class.gems.each do |gem|
    context "when the gem #{gem} is loaded" do
      let(:integration_name) { gem.to_sym }
      let(:integration) { Datadog.registry[integration_name] }

      before do
        expect(integration.patcher.patch_successful).to be_falsey,
                                                        "This test can only run if the integration :#{integration_name} has not patched the environment"
        expect($".find { |x| x.end_with?("/lib/#{gem}.rb") }).to be_nil,
                                                                 "This test can only run if the gem '#{gem}' is not loaded"
      end

      it 'patches the integration on require' do
        # Fork so we don't pollute the current test environment
        expect_in_fork do
          Datadog.configure { |c| c.tracing.instrument integration_name }

          expect { require gem }.to change { integration.patcher.patch_successful }.from(be_falsey).to(be_truthy)
        end
      end
    end
  end
end
