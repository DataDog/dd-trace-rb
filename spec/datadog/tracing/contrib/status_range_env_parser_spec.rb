require 'datadog/tracing/contrib/status_range_env_parser'

RSpec.describe Datadog::Tracing::Contrib::StatusRangeEnvParser do
  describe '.call' do
    [
      ['400', [400]],
      ['400,500', [400, 500]],
      ['400,,500', [400, 500]],
      [',400,500', [400, 500]],
      ['400,500,', [400, 500]],
      ['400-404,500', [400..404, 500]],
      ['400-404,500-504', [400..404, 500..504]],
      ['400-404,444,500-504', [400..404, 444, 500..504]],
    ].each do |input, result|
      it { expect(described_class.call(input)).to eq(result) }
    end
  end
end
