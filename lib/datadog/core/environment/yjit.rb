# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Reports YJIT primitive runtime statistics.
      module YJIT
        # Inline code size
        def self.inline_code_size
          runtime_stats[:inline_code_size]
        end

        # Outlined code size
        def self.outlined_code_size
          runtime_stats[:outlined_code_size]
        end

        # GCed pages
        def self.freed_page_count
          runtime_stats[:freed_page_count]
        end

        # GCed code size
        def self.freed_code_size
          runtime_stats[:freed_code_size]
        end

        # Live pages
        def self.live_page_count
          runtime_stats[:live_page_count]
        end

        # Code GC count
        def self.code_gc_count
          runtime_stats[:code_gc_count]
        end

        # Size of memory region allocated for JIT code
        def self.code_region_size
          runtime_stats[:code_region_size]
        end

        # Total number of object shapes
        def self.object_shape_count
          runtime_stats[:object_shape_count]
        end

        # Size of memory Rust allocated for metadata
        def self.yjit_alloc_size
          runtime_stats[:yjit_alloc_size]
        end

        # Ratio of YJIT-executed instructions
        def self.ratio_in_yjit
          runtime_stats[:ratio_in_yjit]
        end

        def self.available?
          !!(defined?(::RubyVM::YJIT) \
            && ::RubyVM::YJIT.enabled? \
            && ::RubyVM::YJIT.respond_to?(:runtime_stats))
        end

        def self.runtime_stats
          ::RubyVM::YJIT.runtime_stats || {}
        end
      end
    end
  end
end
