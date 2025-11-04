# frozen_string_literal: true

require_relative '../../core/buffer/thread_safe'

# TODO: Replace as module to have 2 implementations CRuby and ThreadSafe one
module Datadog
  module OpenFeature
    module Exposures
      BufferBaseClass =
        Core::Environment::Ext::RUBY_ENGINE == 'ruby' ? Core::Buffer::CRuby : Core::Buffer::ThreadSafe

      class Buffer < BufferBaseClass
        DEFAULT_LIMIT = 1_000

        def initialize(limit = DEFAULT_LIMIT)
          @dropped = 0

          super
        end

        protected

        def drain!
          drained = super

          dropped = @dropped
          @dropped = 0

          [drained, dropped]
        end

        def replace!(item)
          @dropped += 1

          super
        end
      end
    end
  end
end
