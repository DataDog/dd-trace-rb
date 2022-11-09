# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/datadog'
require_relative '../../../distributed/datadog_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::Datadog do
  it_behaves_like 'Datadog distributed format' do
    let(:prepare_key) { proc { |key| "http-#{key}".upcase!.tr('-', '_') } }
  end
end
