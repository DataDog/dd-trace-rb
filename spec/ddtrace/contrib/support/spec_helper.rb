require 'spec_helper'

RSpec.configure do |config|
  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require 'ddtrace/contrib/patcher'
  config.before(:each) do
    allow_any_instance_of(Datadog::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end
end
