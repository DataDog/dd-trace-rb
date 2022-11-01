# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/b3'
require_relative '../../distributed/b3_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::B3 do
  it_behaves_like 'B3 distributed format' do
    let(:prepare_key) { proc { |key| "http-#{key}".upcase!.tr('-', '_') } }
  end
end
