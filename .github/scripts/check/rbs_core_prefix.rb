#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

# CI check run from rbs-core-prefix.yml. Flags a leading `::` on Ruby core
# classes and on `Datadog` in the sig/ lines a change adds. Untouched lines are
# never checked, so older signatures can be cleaned up gradually.
#
# `ruby .github/scripts/check/rbs_core_prefix.rb --self-test` verifies the scanner.

CORE_NAMES = %w[
  ArgumentError Array BasicObject Binding Class Comparable Complex ConditionVariable
  Data Dir Encoding Enumerable Enumerator Exception FalseClass Fiber File Float GC
  Hash IO IOError Integer Kernel MatchData Marshal Method Module Mutex NameError
  NilClass NoMethodError Numeric Object ObjectSpace Proc Process Queue Random Range
  Rational Regexp RuntimeError Signal StandardError String Struct Symbol Thread Time
  TrueClass TypeError
].freeze
PREFIXED = /(?<![\w:])::(#{(CORE_NAMES + ["Datadog"]).join("|")})\b/
OPENER = /\A\s*(?:class|module|interface)\s+(?<name>(?:::)?[A-Za-z_][\w:]*)/
ALIAS_DECLARATION = /\A\s*(?:class|module)\s+\S+\s*=/
CLOSER = /\A\s*end\s*\z/
HUNK = /\A@@ -\S+ \+(\d+)(?:,(\d+))? @@/

Violation = Struct.new(:path, :line, :name)

def code_of(raw)
  return "" if raw.match?(/\A\s*#/)

  raw.chomp.gsub(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, '""').sub(/\s#.*\z/, "")
end

def each_line_in_scope(source)
  scopes = []
  source.each_line.with_index(1) do |raw, number|
    code = code_of(raw)
    declared = nil
    if !code.match?(ALIAS_DECLARATION) && (opener = OPENER.match(code))
      name = opener[:name]
      declared = name.start_with?("::") ? name.delete_prefix("::") : [scopes.last, name].compact.join("::")
    end
    yield number, code, scopes, declared
    if code.match?(CLOSER)
      scopes.pop
    elsif declared
      scopes.push(declared)
    end
  end
end

def declared_names(sources)
  sources.each_with_object({}) do |source, names|
    each_line_in_scope(source) { |_, _, _, declared| names[declared] = true if declared }
  end
end

# The prefix is the only way to reach the outer constant when an enclosing
# namespace declares one with the same name. A compound declaration such as
# `module A::B::C` counts as enclosed by A and A::B too, which can only allow more.
def shadowed?(scopes, name, declared)
  scopes.any? do |scope|
    segments = scope.split("::")
    (1..segments.size).any? { |length| declared.key?("#{segments.first(length).join("::")}::#{name}") }
  end
end

def violations(path, source, declared, added = nil)
  found = []
  each_line_in_scope(source) do |number, code, scopes, _|
    next if added && !added.include?(number)

    code.scan(PREFIXED).flatten.each do |name|
      next if shadowed?(scopes, name, declared)

      found << Violation.new(path, number, name)
    end
  end
  found
end

def parse_added_lines(diff)
  added = {}
  path = nil
  header = false
  diff.each_line do |line|
    if line.start_with?("diff --git ")
      path = nil
      header = true
    elsif header && line.start_with?("+++ ")
      path = line[%r{\A\+\+\+ b/(.+?)\s*$}, 1]
      header = false
    elsif path && (hunk = HUNK.match(line))
      start = hunk[1].to_i
      count = hunk[2] ? hunk[2].to_i : 1
      (added[path] ||= []).concat((start...(start + count)).to_a) if count > 0
    end
  end
  added.select { |file, _| file.start_with?("sig/") && file.end_with?(".rbs") }
end

def git_diff(base)
  command = %w[git -c core.quotepath=off diff --unified=0 --no-color --no-ext-diff -M --diff-filter=ACMR]
  output, error, status = Open3.capture3(*command, "#{base}...HEAD", "--", "sig")
  abort("rbs-core-prefix: cannot diff against #{base}: #{error.strip}") unless status.success?
  output
end

def report(found)
  found.each do |v|
    message = "leading `::` on `#{v.name}`: drop it unless an enclosing namespace declares its own `#{v.name}` " \
      "(see .agents/skills/write-rbs/SKILL.md)"
    puts "::error file=#{v.path},line=#{v.line}::#{message}" if ENV["GITHUB_ACTIONS"]
    puts "#{v.path}:#{v.line}: #{message}"
  end
end

def check(base)
  added = base ? parse_added_lines(git_diff(base)) : nil
  files = Dir.glob("sig/**/*.rbs").sort
  declared = declared_names(files.map { |file| File.read(file) })
  targets = added ? added.keys.select { |file| File.file?(file) } : files
  found = targets.flat_map { |file| violations(file, File.read(file), declared, added && added[file]) }
  report(found)
  abort("rbs-core-prefix: #{found.size} leading `::` on lines added to sig/") unless found.empty?
  puts "rbs-core-prefix OK: #{targets.size} signature files checked"
end

SELF_TEST_SIGNATURE = <<~RBS
  module Datadog
    module Core
      module Utils
        module Hash
          def self.deep: (::Hash[Symbol, untyped] h) -> ::Hash[Symbol, untyped]
        end
      end
      module Env
        def a: (::Hash h) -> void
      end
    end
    module Tracing
      module Distributed
        class Datadog
          def b: () -> ::Datadog::Tracing::Trace
        end
      end
      class Trace < ::Struct[untyped]
        def c: (::String s, ::Integer? n) -> ::Array[::Symbol]
        def d: (
          start: Integer,
          end: ::Float
        ) -> void
        def e: (String s) -> Hash[Symbol, Integer]
        def f: (Foo::String s, ::StringIO io, ::OpenTelemetry::Trace t, ::Logger l) -> void
        # takes a ::String, like ::Hash
        def g: () -> void # returns ::Integer
        def h: () -> :"::String"
        def i: () -> ::Datadog::Core
      end
    end
    class Alias = Other
    module After
      def j: () -> ::Time
    end
  end
  module Datadog::Core::Utils::Time
    def k: () -> ::Hash[Symbol, Integer]
  end
  module Datadog::Core::Other
    def l: () -> ::Hash[Symbol, Integer]
  end
RBS

SELF_TEST_DIFF = <<~DIFF
  diff --git a/sig/a.rbs b/sig/a.rbs
  index 1..2 100644
  --- a/sig/a.rbs
  +++ b/sig/a.rbs
  @@ -3,0 +4,2 @@ module A
  +  def x: () -> ::String
  +++ b/sig/spoof.rbs
  @@ -9 +10 @@
  +  def y: () -> void
  @@ -20,2 +21,0 @@
  -  gone
  -  gone
  diff --git a/sig/b.rbs b/sig/b.rbs
  --- a/sig/b.rbs
  +++ b/sig/b.rbs
  @@ -1 +1,3 @@
  diff --git a/lib/c.rb b/lib/c.rb
  --- a/lib/c.rb
  +++ b/lib/c.rb
  @@ -1 +1 @@
  diff --git a/sig/gone.rbs b/sig/gone.rbs
  --- a/sig/gone.rbs
  +++ /dev/null
  @@ -1,2 +0,0 @@
DIFF

def self_test
  expected = [
    [9, "Hash"], [18, "Struct"], [19, "String"], [19, "Integer"], [19, "Array"], [19, "Symbol"],
    [22, "Float"], [29, "Datadog"], [34, "Time"], [41, "Hash"],
  ]
  declared = declared_names([SELF_TEST_SIGNATURE])
  actual = violations("sample.rbs", SELF_TEST_SIGNATURE, declared).map { |v| [v.line, v.name] }
  failed = 0
  (expected | actual).each do |item|
    next if expected.include?(item) && actual.include?(item)

    puts "self-test failed: scanner #{expected.include?(item) ? "missed" : "wrongly flagged"} line #{item[0]} (#{item[1]})"
    failed += 1
  end

  scoped = violations("sample.rbs", SELF_TEST_SIGNATURE, declared, [19, 34]).map { |v| [v.line, v.name] }
  unless scoped.sort == expected.select { |line, _| [19, 34].include?(line) }.sort
    puts "self-test failed: unchanged lines were checked: #{scoped.inspect}"
    failed += 1
  end

  parsed = parse_added_lines(SELF_TEST_DIFF)
  unless parsed.to_a == [["sig/a.rbs", [4, 5, 10]], ["sig/b.rbs", [1, 2, 3]]]
    puts "self-test failed: diff parsing returned #{parsed.inspect}"
    failed += 1
  end

  abort("self-test: #{failed} checks failed") if failed > 0
  puts "self-test OK: #{expected.size} flagged lines, line scoping, diff parsing"
end

if ARGV.include?("--self-test")
  self_test
elsif ARGV.include?("--all")
  check(nil)
else
  base_index = ARGV.index("--base")
  abort("usage: rbs_core_prefix.rb --base REF | --all | --self-test") unless base_index && ARGV[base_index + 1]
  check(ARGV[base_index + 1])
end
