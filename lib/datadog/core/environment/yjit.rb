# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Reports YJIT primitive runtime statistics.
      module YJIT
        module_function

        def inline_code_size
          ::RubyVM::YJIT.runtime_stats[:inline_code_size]
        end

        def outlined_code_size
          ::RubyVM::YJIT.runtime_stats[:outlined_code_size]
        end

        def freed_page_count
          ::RubyVM::YJIT.runtime_stats[:freed_page_count]
        end

        def freed_code_size
          ::RubyVM::YJIT.runtime_stats[:freed_code_size]
        end

        def live_page_count
          ::RubyVM::YJIT.runtime_stats[:live_page_count]
        end

        def code_gc_count
          ::RubyVM::YJIT.runtime_stats[:code_gc_count]
        end

        def code_region_size
          ::RubyVM::YJIT.runtime_stats[:code_region_size]
        end

        def object_shape_count
          ::RubyVM::YJIT.runtime_stats[:object_shape_count]
        end

        def yjit_alloc_size
          ::RubyVM::YJIT.runtime_stats[:yjit_alloc_size]
        end

        def ratio_in_yjit
          stats = ::RubyVM::YJIT.runtime_stats
          stats[:ratio_in_yjit] if stats.key?(:ratio_in_yjit)
        end

        def available?
          !!(defined?(::RubyVM::YJIT) \
            && ::RubyVM::YJIT.enabled? \
            && ::RubyVM::YJIT.respond_to?(:runtime_stats))
        end
      end
    end
  end
end
