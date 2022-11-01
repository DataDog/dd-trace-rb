# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/propagation'
require_relative '../../distributed/propagation_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::Propagation do
  it_behaves_like 'Distributed tracing propagator' do
    subject(:propagation) { described_class.new }

    let(:prepare_key) { proc { |key| "http-#{key}".upcase!.tr('-', '_') } }
  end
end
