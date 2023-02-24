require 'spec_helper'

require 'datadog/core/telemetry/http/env'

RSpec.describe Datadog::Core::Telemetry::Http::Env do
  subject(:env) { described_class.new }

  describe '#initialize' do
    it { is_expected.to have_attributes(headers: {}) }
  end

  it 'has request attributes' do
    is_expected.to respond_to(:path)
    is_expected.to respond_to(:path=)
    is_expected.to respond_to(:body)
    is_expected.to respond_to(:body=)
    is_expected.to respond_to(:headers)
    is_expected.to respond_to(:headers=)
  end
end
