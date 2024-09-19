require 'spec_helper'
require 'datadog/core/buffer/shared_examples'

require 'datadog/core/buffer/cruby'

RSpec.describe Datadog::Core::Buffer::CRuby do
  before { skip unless PlatformHelpers.mri? }

  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'
end
