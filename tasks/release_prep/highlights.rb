# frozen_string_literal: true

require_relative "../release_prep"

# The unreleased/highlights.md file: free-form release-page highlights for the
# next release. Exists-or-not as one object, so callers never branch on
# File.exist? or nil.
module ReleasePrep
  class Highlights
    FILE = "highlights.md"

    attr_reader :path

    def self.read(dir: "unreleased")
      new(path: File.join(dir, FILE))
    end

    def initialize(path:)
      @path = path
    end

    def exists?
      File.exist?(@path)
    end

    def to_s
      exists? ? File.read(@path) : ""
    end

    def empty?
      to_s.strip.empty?
    end

    def delete!
      File.delete(@path) if exists?
      nil
    end
  end
end
