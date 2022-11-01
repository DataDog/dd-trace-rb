# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/grpc/distributed/datadog'
require_relative '../../distributed/datadog_spec'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Distributed::Datadog do
  it_behaves_like 'Datadog distributed format'
end
