require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/redis/patcher'

RSpec.describe Datadog::Tracing::Contrib::Redis::Patcher do
  describe '.default_tags' do
    it do
      result = described_class.default_tags

      expect(result).to include(start_with('patcher:'))

      if Datadog::Tracing::Contrib::Redis::Integration.redis_version
        expect(result).to include(start_with('target_redis_version:'))
      end

      if Datadog::Tracing::Contrib::Redis::Integration.redis_client_version
        expect(result).to include(start_with('target_redis_client_version:'))
      end
    end
  end
end
