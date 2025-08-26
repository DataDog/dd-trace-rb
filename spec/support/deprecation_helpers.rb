module DeprecationHelpers
  RSpec.shared_context 'log deprecation when deprecated env var is set' do |message_matcher|
    before do
      # This is initialized during app startup and should not change during app lifecycle
      # However in our tests, we change the environment variables without completely resetting the app
      # This is why we reset this variable here.
      Datadog.instance_variable_set(:@log_deprecations_called_with, nil)
    end

    it 'logs deprecation' do
      expect(Datadog::Core).to receive(:log_deprecation).with(any_args) do |&message_block|
        expect(message_block.call).to match(message_matcher) if message_matcher
      end
      # Reinitialize components (which logs deprecations again as we've reset @log_deprecations_called_with)
      Datadog.configure {}
    end
  end
end
