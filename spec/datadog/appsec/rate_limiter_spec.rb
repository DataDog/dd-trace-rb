require 'datadog/appsec/spec_helper'
require 'datadog/appsec/rate_limiter'

RSpec.describe Datadog::AppSec::RateLimiter do
  before { described_class.reset! }

  describe '#limit' do
    context 'in different threads' do
      before { stub_const("#{described_class}::THREAD_KEY", :__spec_instance) }

      it 'creates separate rate limiter per thread' do
        thread_1 = Thread.new do
          described_class.thread_local
        end

        thread_2 = Thread.new do
          described_class.thread_local
        end

        thread_1.join
        thread_2.join

        rate_limiter_1 = thread_1.thread_variable_get(:__spec_instance)
        rate_limiter_2 = thread_2.thread_variable_get(:__spec_instance)

        expect(rate_limiter_1).not_to be(rate_limiter_2)
      end
    end
  end
end
