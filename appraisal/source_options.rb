# Teach Appraisal's DSL to carry options on `source`.
#
# Appraisal 2.4.1's `BundlerDSL#source` accepts only a URL and renders it as a
# bare `source "..."`, so a supply-chain cooldown declaration would raise
# `ArgumentError` on load and could never reach a generated gemfile. Store the
# options alongside the URL and render them back out.
#
# `source_entry_for_dup` is aliased at class-definition time and `Gemfile#dup`
# builds a fresh object, so this patches the class rather than the singleton the
# way `generate.rb` does for `eval_gemfile`/`gemspec`.

require 'appraisal/appraisal'

module Appraisal
  class BundlerDSL
    # Remove the upstream definitions first so redefining them here does not
    # emit "method redefined" warnings under `-w`.
    remove_method(:source) if method_defined?(:source)
    remove_method(:source_entry) if private_method_defined?(:source_entry)

    def source(source, options = {}, &block)
      if block_given?
        @source_blocks[source] ||=
          Source.new(source).tap { |g| g.git_sources = @git_sources.dup }
        @source_blocks[source].run(&block)
      else
        @sources << [source, options]
      end
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

    alias_method :source_entry_for_dup, :source_entry
  end
end
