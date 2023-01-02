# frozen_string_literal: false
# typed: false

require_relative '../../../distributed/fetcher'

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        module Distributed
          class Fetcher < Tracing::Distributed::Fetcher
          end
        end
      end
    end
  end
end
