# frozen_string_literal: true

require_relative "../release_prep"
require_relative "fragment"

# The collection of pending changelog fragments (unreleased/*.json), excluding
# the examples/ templates: the set of changes the next release will announce.
module ReleasePrep
  class Fragments
    include Enumerable

    def self.read_all(dir: "unreleased")
      new(Dir.glob(File.join(dir, "*.json")).sort.map { |path| Fragment.read(path) })
    end

    def self.read_examples(dir: "unreleased")
      new(Dir.glob(File.join(dir, "examples", "*.json")).sort.map { |path| Fragment.read(path) })
    end

    def initialize(fragments)
      @fragments = fragments
    end

    def each(&block)
      @fragments.each(&block)
    end

    def size
      @fragments.size
    end

    def empty?
      @fragments.empty?
    end

    # Renders the pending fragments as Markdown: highlights (if given), then
    # one section per fragment type, fragments sorted by prefix. Plain
    # Markdown only; linkification is changelog:format's job.
    def render(highlights: nil)
      return highlights.to_s if @fragments.empty?

      sections = Fragment::TYPES.map do |type|
        type_fragments = @fragments.select { |fragment| fragment.type == type }
        next if type_fragments.empty?

        lines = type_fragments.sort_by(&:prefix).map(&:to_s)
        "### #{type}\n\n#{lines.join("\n")}"
      end.compact

      [highlights, *sections].compact.join("\n\n").sub(/\n*\z/, "")
    end

    # Deletes exactly the files backing these fragments (and highlights.md
    # when given), never anything else in unreleased/.
    def consume!(highlights_path: nil)
      @fragments.each(&:delete!)
      File.delete(highlights_path) if highlights_path && File.exist?(highlights_path)
      nil
    end
  end
end
