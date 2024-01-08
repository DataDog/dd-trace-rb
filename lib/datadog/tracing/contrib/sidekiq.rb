# frozen_string_literal: true

require_relative 'component'
require_relative 'sidekiq/integration'
require_relative 'sidekiq/distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      # `Sidekiq` integration public API
      module Sidekiq
        def self.inject(digest, data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.inject!(digest, data)
        end

        def self.extract(data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.extract(data)
        end

        Contrib::Component.register('sidekiq') do |config|
          distributed_tracing = config.tracing.distributed_tracing
          distributed_tracing.propagation_style # TODO: do we still need this?

          @propagation = Sidekiq::Distributed::Propagation.new(
            propagation_inject_style: distributed_tracing.propagation_inject_style,
            propagation_extract_style: distributed_tracing.propagation_extract_style,
            propagation_extract_first: distributed_tracing.propagation_extract_first
          )
        end
      end
    end
  end
end
