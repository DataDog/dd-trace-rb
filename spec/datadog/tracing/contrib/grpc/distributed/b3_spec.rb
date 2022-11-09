# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/grpc/distributed/b3'
require_relative '../../../distributed/b3_spec'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Distributed::B3 do
  it_behaves_like 'B3 distributed format'
end
