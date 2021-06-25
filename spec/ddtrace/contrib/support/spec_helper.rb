require 'spec_helper'

require_relative 'matchers'
require_relative 'resolver_helpers'
require_relative 'tracer_helpers'

require 'ddtrace' # Contrib tests require tracer components to be initialized
require 'ddtrace/contrib/extensions'

RSpec.configure do |config|
  config.include Contrib::TracerHelpers

  # TODO: remove me
  # config.before do
  #   The majority of Contrib tests requires the full tracer setup
    # if !defined?(preload_ddtrace) || preload_ddtrace
    #   require 'ddtrace'
    # end
  # end

  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require 'ddtrace/contrib/patcher'
  config.before do
    allow_any_instance_of(Datadog::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end

  # Ensures all tracer runtime objects and resources, alongside any
  # stateful data (e.g. configuration) is disposed and reinitialized.
  #
  # On each RSpec example, the tracer will behave like a newly initialized
  # application, one that has just invoked `require 'ddtrace'`.
  #
  # This is done :before and not :after each example as doing so :after
  # can create noise for test assertions, for example:
  # +expect(Datadog).to receive(:shutdown!).once+
  config.before do
    # TODO: this was here before, still needed?
    # Datadog.send(:restart!)
  end
end
