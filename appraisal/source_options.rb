require 'appraisal/appraisal'

module Appraisal
  module SourceOptions
    # Appraisal's `BundlerDSL#source` takes a URL and nothing else
    # Change to carry the options through and render them back out.
    def source(source, options = {}, &block)
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

    # `BundlerDSL` aliases this at class-definition time, so without re-aliasing
    # `Gemfile#dup` replays through the original and emits the raw
    # `[url, options]` array.
    alias_method :source_entry_for_dup, :source_entry
  end

  BundlerDSL.prepend(SourceOptions)
end
