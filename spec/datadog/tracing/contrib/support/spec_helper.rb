require 'spec_helper'

require_relative 'matchers'
require_relative 'resolver_helpers'
require_relative 'tracer_helpers'

RSpec.configure do |config|
  config.include Contrib::TracerHelpers

  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require 'datadog/tracing/contrib/patcher'
  config.before do
    allow_any_instance_of(Datadog::Tracing::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end

  # Ensure tracer environment is clean before running tests.
  #
  # This is done :before and not :after because doing so after
  # can create noise for test assertions. For example:
  # +expect(Datadog).to receive(:shutdown!).once+
  config.before do
    Datadog.shutdown!
    without_warnings { Datadog.configuration.reset! }
  end
end
