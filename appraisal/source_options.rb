# Teach Appraisal's DSL to carry options on `source`.
#
# Appraisal 2.4.1's `BundlerDSL#source` accepts only a URL and renders it as a
# bare `source "..."`, so a supply-chain cooldown declaration would raise
# `ArgumentError` on load and could never reach a generated gemfile. Store the
# options alongside the URL and render them back out.
#
# Prepended rather than reopened so the block form can delegate upstream with
# `super`, and so nothing is redefined out from under the original class.

require 'appraisal/appraisal'

module Appraisal
  module SourceOptions
    def source(source, options = {}, &block)
      # The block form declares a scoped source block rather than a top-level
      # `source` line; upstream handles it and options do not apply.
      return super(source, &block) if block

      @sources << [source, options]
    end

    private

    def source_entry
      @sources.uniq.map do |source, options|
        if options.nil? || options.empty?
          "source #{source.inspect}"
        else
          rendered = options.map { |key, value| "#{key}: #{value.inspect}" }.join(', ')
          "source #{source.inspect}, #{rendered}"
        end
      end.join("\n")
    end

    # `BundlerDSL` aliases this at class-definition time, so the alias still
    # points at the original renderer and `Gemfile#dup` — which replays through
    # it — would emit the raw `[url, options]` array. Re-alias here so the dup
    # path resolves to the definition above.
    alias_method :source_entry_for_dup, :source_entry
  end

  BundlerDSL.prepend(SourceOptions)
end
