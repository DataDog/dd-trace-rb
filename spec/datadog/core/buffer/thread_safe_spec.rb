require 'spec_helper'
require 'datadog/core/buffer/shared_examples'

require 'datadog/core/buffer/thread_safe'

RSpec.describe Datadog::Core::Buffer::ThreadSafe do
  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'
end
