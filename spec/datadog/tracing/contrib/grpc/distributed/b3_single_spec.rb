# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/grpc/distributed/b3_single'
require_relative '../../distributed/b3_single_spec'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Distributed::B3Single do
  it_behaves_like 'B3 Single distributed format'
end
