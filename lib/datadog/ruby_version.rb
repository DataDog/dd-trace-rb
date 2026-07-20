# frozen_string_literal: true

module Datadog
  # Compares the running Ruby against version requirements.
  #
  # Lexical comparisons against `RUBY_VERSION` are subtly wrong: `RUBY_VERSION < "3.2.3"` is also
  # `true` on 3.2.10 and 3.2.11, since those sort *before* "3.2.3" as strings.
  #
  # @example
  #   RubyVersion.is?(">= 3.2", "< 3.2.3") # => true on Ruby 3.2.0, 3.2.1, 3.2.2 (NOT 3.2.3+, NOT 3.2.10+)
  module RubyVersion
    extend RubyVersion # steep currently needs this (instead of extend self or def self.is?) for the inline rbs to work

    CURRENT_RUBY_VERSION = Gem::Version.new(RUBY_VERSION) #: ::Gem::Version
    private_constant :CURRENT_RUBY_VERSION

    # Returns `true` when the running Ruby satisfies ALL of the given requirements. Each uses the
    # same syntax as a gem dependency (e.g. `">= 3.1"`, `">= 3.2"`, `"< 3.2.3"`).
    #
    # @rbs (*String requirements, ?ruby_version: ::Gem::Version) -> bool
    def is?(*requirements, ruby_version: CURRENT_RUBY_VERSION)
      Gem::Requirement.new(*requirements).satisfied_by?(ruby_version)
    end
  end
end
