# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/b3_single'
require_relative '../../../distributed/b3_single_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::B3Single do
  it_behaves_like 'B3 Single distributed format' do
    let(:prepare_key) { proc { |key| "http-#{key}".upcase!.tr('-', '_') } }
  end
end
