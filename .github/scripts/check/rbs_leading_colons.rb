#!/usr/bin/env ruby
# frozen_string_literal: true

# CI check for RBS signatures, run from rbs-leading-colons.yml on pull requests.
# Flags lines a pull request adds to sig/**/*.rbs that write a Ruby core
# class with a leading `::` (for example `::String`). The write-rbs skill
# forbids it, and reviewers otherwise catch it by hand on every signature.
# Only added lines are checked, so signatures that predate the rule never
# fail the build.
#
# A leading `::` stays valid where an enclosing namespace declares a class or
# module with the same name (for example `Datadog::Core::Utils::Hash`), because
# the bare name would resolve to that declaration. The scan therefore tracks
# the lexical namespace and skips shadowed names.
#
# Run locally with:
#   BASE_REF=master PR_HEAD_SHA=HEAD ruby .github/scripts/check/rbs_leading_colons.rb
# Run `ruby .github/scripts/check/rbs_leading_colons.rb --self-test` to
# verify the scanner.

require "open3"

CORE_CLASSES = %w[
  ArgumentError Array Class Comparable Dir Enumerable Exception File Float Hash IO Integer Method Module Mutex
  NilClass Numeric Object Proc Process Queue Random Range Rational Regexp RuntimeError StandardError String
  Struct Symbol Thread Time
].freeze
LEADING_COLONS = /(?<![\w:])::(#{CORE_CLASSES.join("|")})\b/
DECLARATION = /\A\s*(?:class|module|interface)\s+(?:::)?([A-Za-z_]\w*(?:::\w+)*)/
COMMENT_LINE = /\A\s*#/
STRING_LITERAL = /"(?:[^"\\]|\\.)*"/

# Returns the lines of an RBS source with the lexical namespace each one is
# resolved in, plus every namespace the source declares. A declaration line
# resolves in the scope that encloses it, which is how a subclass of `::Hash`
# inside `Hash` is told apart from a reference to the declaring module.
def parse(source)
  frames = []
  lines = []
  declared = []
  source.each_line.with_index(1) do |line, number|
    code = COMMENT_LINE.match?(line) ? "" : line
    namespace = frames.flatten
    lines << [number, code, namespace]
    if (match = code.match(DECLARATION))
      names = match[1].split("::")
      names.each_index { |index| declared << (namespace + names.first(index + 1)).join("::") }
      frames.push(names)
    elsif code.match?(/\A\s*end\s*\z/)
      frames.pop
    end
  end
  [lines, declared]
end

def shadowed?(name, namespace, declared)
  (1..namespace.size).any? { |depth| declared.include?((namespace.first(depth) + [name]).join("::")) }
end

# `added` is the set of line numbers the pull request added, or nil to check
# every line.
def violations(source, declared, added)
  lines, local = parse(source)
  known = declared + local
  lines.each_with_object([]) do |(number, code, namespace), found|
    next if added && !added.include?(number)

    code.gsub(STRING_LITERAL, '""').scan(LEADING_COLONS).flatten.each do |name|
      found << [number, name] unless shadowed?(name, namespace, known)
    end
  end
end

def git(*args)
  output, status = Open3.capture2("git", *args)
  abort("rbs-leading-colons: `git #{args.join(" ")}` failed with exit #{status.exitstatus}") unless status.success?
  output
end

# Maps each added or modified file to the line numbers the diff adds. Rename
# detection is on, so a moved file with unchanged content has no hunks and
# its existing lines are not reported as new.
def added_lines_by_file(diff)
  path = nil
  diff.each_line.with_object({}) do |line, files|
    if line.start_with?("diff --git ")
      path = nil
    elsif line.start_with?("+++ ")
      path = line.start_with?("+++ b/") ? line.chomp.delete_prefix("+++ b/") : nil
      files[path] = [] if path
    elsif path && (hunk = line.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
      start = hunk[1].to_i
      files[path].concat((start...(start + (hunk[2] || "1").to_i)).to_a)
    end
  end
end

def declared_namespaces
  Dir.glob(["sig/**/*.rbs", "vendor/rbs/**/*.rbs"]).flat_map { |path| parse(File.read(path)).last }
end

def report(path, number, name)
  message = "Write `#{name}`, not `::#{name}`: a leading `::` is only for a name an enclosing namespace shadows."
  if ENV["GITHUB_ACTIONS"] == "true"
    puts "::error file=#{path},line=#{number}::#{message}"
  else
    puts "#{path}:#{number}: #{message}"
  end
end

def check_pull_request
  base_ref = ENV.fetch("BASE_REF") { abort("rbs-leading-colons: BASE_REF is not set") }
  head = ENV.fetch("PR_HEAD_SHA") { abort("rbs-leading-colons: PR_HEAD_SHA is not set") }
  range = "origin/#{base_ref}...#{head}"

  diff = git("diff", "--unified=0", "--find-renames", "--diff-filter=AMR", range, "--", "sig")
  files = added_lines_by_file(diff).select { |path, lines| path.end_with?(".rbs") && !lines.empty? }
  declared = files.empty? ? [] : declared_namespaces

  failed = false
  files.each do |path, added|
    violations(git("show", "#{head}:#{path}"), declared, added).each do |number, name|
      report(path, number, name)
      failed = true
    end
  end

  puts "RBS leading `::` check OK" unless failed
  exit(1) if failed
end

def self_test
  hash_module = "module Datadog\n  module Core\n    module Utils\n      module Hash\n        def self.deep: " \
    "(::Hash[Symbol, untyped] h) -> ::Hash[Symbol, untyped]\n      end\n    end\n  end\nend\n"
  cases = {
    "rooted core classes in a signature" => ["class Foo\n  def a: (::String x) -> ::Integer\nend\n", nil, 2],
    "plain core classes" => ["class Foo\n  def a: (String x) -> Integer?\nend\n", nil, 0],
    "nested generics" => ["class Foo\n  @a: Hash[::Symbol, ::String]\nend\n", nil, 2],
    "comment lines are skipped" => ["# def a: (::Hash[::String, any]) -> void\nclass Foo\nend\n", nil, 0],
    "qualified names are not rooted" => ["class Foo\n  def a: () -> Bar::String\nend\n", nil, 0],
    "stdlib and unlisted names" => ["class Foo\n  def a: (::StringIO io) -> ::Logger\nend\n", nil, 0],
    "string literals are skipped" => ["class Foo\n  KEY: \"::String\"\nend\n", nil, 0],
    "own-library roots are out of scope" => ["class Foo\n  def a: () -> ::Datadog::Core::Foo\nend\n", nil, 0],
    "name shadowed by an enclosing module" => [hash_module, nil, 0],
    "shadow does not leak to a sibling namespace" =>
      [hash_module + "module Datadog\n  module Other\n    def x: (::Hash[Symbol, untyped] h) -> void\n  end\nend\n",
        nil, 1],
    "multi-line signature, only added line" =>
      ["class Foo\n  def call:\n    (::String name,\n     ::Integer count) -> void\nend\n", [4], 1],
    "pre-existing line is ignored" => ["class Foo\n  def a: () -> ::String\n  def b: () -> ::String\nend\n", [3], 1],
    "an `end:` keyword label does not close a namespace" =>
      ["module Datadog\n  module Core\n    module Utils\n      module Hash\n        def self.r: (\n" \
        "  end: Integer,\n  ?h: ::Hash[Symbol, untyped]\n) -> void\n      end\n    end\n  end\nend\n", nil, 0],
    "no added lines" => ["class Foo\n  def a: () -> ::String\nend\n", [], 0],
  }
  failed = 0
  cases.each do |name, (source, added, expected)|
    actual = violations(source, [], added).size
    next if actual == expected

    puts "self-test failed: #{name}: expected #{expected}, got #{actual}"
    failed += 1
  end

  diff = "diff --git a/sig/a.rbs b/sig/a.rbs\n--- a/sig/a.rbs\n+++ b/sig/a.rbs\n@@ -3 +3 @@\n" \
    "@@ -9,2 +10,3 @@\n@@ -20,4 +25,0 @@\n" \
    "diff --git a/sig/b.rbs b/sig/b.rbs\n--- a/sig/b.rbs\n+++ b/sig/b.rbs\n@@ -1,0 +2 @@\n" \
    "diff --git a/sig/old.rbs b/sig/new.rbs\nsimilarity index 100%\nrename from sig/old.rbs\nrename to sig/new.rbs\n" \
    "diff --git a/sig/gone.rbs b/sig/gone.rbs\n--- a/sig/gone.rbs\n+++ /dev/null\n@@ -1,2 +0,0 @@\n"
  expected_files = {"sig/a.rbs" => [3, 10, 11, 12], "sig/b.rbs" => [2]}
  unless added_lines_by_file(diff) == expected_files
    puts "self-test failed: diff parsing: got #{added_lines_by_file(diff).inspect}"
    failed += 1
  end

  total = cases.size + 1
  abort("self-test: #{failed} of #{total} cases failed") if failed > 0
  puts "self-test OK: #{total} cases"
end

if ARGV.first == "--self-test"
  self_test
else
  check_pull_request
end
