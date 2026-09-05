# frozen_string_literal: true

require_relative "../release_prep"

# The unreleased/highlights.md file: free-form release-page highlights for
# the next release. .read returns a Highlights for a present file and the
# inert Missing null object otherwise, so callers never branch on existence.
module ReleasePrep
  class Highlights
    FILE = "highlights.md"

    attr_reader :path

    def self.read(dir: "unreleased")
      path = File.join(dir, FILE)
      File.exist?(path) ? new(path) : Missing.new
    end

    def initialize(path)
      @path = path
    end

    def to_s
      File.read(@path)
    end

    def empty?
      to_s.strip.empty?
    end

    def delete!
      File.delete(@path)
      nil
    end

    # Null object for the absent case: same API, inert behavior.
    class Missing
      def to_s
        ""
      end

      def empty?
        true
      end

      def delete!
        nil
      end
    end
  end
end
