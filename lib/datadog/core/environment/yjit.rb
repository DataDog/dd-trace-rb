# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Reports YJIT primitive runtime statistics.
      module YJIT
        module_function

        # Inline code size
        def inline_code_size
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:inline_code_size]
        end

        # Outlined code size
        def outlined_code_size
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:outlined_code_size]
        end

        # GCed pages
        def freed_page_count
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:freed_page_count]
        end

        # GCed code size
        def freed_code_size
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:freed_code_size]
        end

        # Live pages
        def live_page_count
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:live_page_count]
        end

        # Code GC count
        def code_gc_count
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:code_gc_count]
        end

        # Size of memory region allocated for JIT code
        def code_region_size
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:code_region_size]
        end

        # Total number of object shapes
        def object_shape_count
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:object_shape_count]
        end

        # Size of memory Rust allocated for metadata
        def yjit_alloc_size
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
          stats[:yjit_alloc_size]
        end

        # Ratio of YJIT-executed instructions
        def ratio_in_yjit
          stats = ::RubyVM::YJIT.runtime_stats #: Hash[untyped, untyped]
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
