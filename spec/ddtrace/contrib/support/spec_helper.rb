require 'spec_helper'

require_relative 'matchers'
require_relative 'tracer_helpers'

RSpec.configure do |config|
  config.include Contrib::TracerHelpers

  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require 'ddtrace/contrib/patcher'
  config.before(:each) do
    allow_any_instance_of(Datadog::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end

  # Ensure tracer environment is clean before running tests.
  #
  # This is done :before and not :after because doing so after
  # can create noise for test assertions. For example:
  # +expect(Datadog).to receive(:shutdown!).once+
  config.before(:each) do
    Datadog.shutdown!
    Datadog.configuration.reset!
  end
end
