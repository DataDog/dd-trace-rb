#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

# CI check for RBS signatures, run by `rake rbs:leading_colon`, which the
# steep:check task requires. Fails when a pull request adds a leading `::` to a
# Ruby core class or to the library's own `Datadog` namespace in sig/**/*.rbs,
# as .agents/skills/write-rbs requires. Only added lines are checked, so
# signatures that predate the rule never fail the build.
#
# The `::` stays legal when an enclosing namespace declares a constant with the
# same name, for example `Hash` inside `Datadog::Core::Utils`. The check finds
# those by indexing every declaration in sig/.
#
# The base branch comes from BASE_REF, or from GITHUB_BASE_REF on pull request
# runs. Without either, there is nothing to compare against and the check is
# skipped. Run `BASE_REF=master ruby .github/scripts/check/rbs_leading_colon.rb`
# to check the current branch against origin/master, or add `--self-test` to
# verify the detection logic.

# Core classes and modules that need no `require`. Standard-library and
# third-party names (`::Logger`, `::Rack`) are deliberately absent.
FLAGGED_NAMES = %w[
  Array BasicObject Binding Class Comparable ConditionVariable Dir Encoding
  Enumerable Enumerator Errno Exception FalseClass Fiber File Float GC Hash IO
  Integer Kernel Marshal MatchData Math Method Module Mutex NilClass Numeric
  Object ObjectSpace Proc Process Queue Random Range Rational Regexp Signal
  String Struct Symbol Thread ThreadGroup Time TrueClass UnboundMethod
  ArgumentError EOFError FloatDomainError FrozenError IOError IndexError
  Interrupt KeyError LoadError LocalJumpError NameError NoMethodError
  NotImplementedError RangeError RuntimeError ScriptError SecurityError
  SignalException StandardError StopIteration SystemCallError SystemExit
  TypeError ZeroDivisionError
  Datadog
].freeze

# A `::` that starts a type. `Foo::Bar` does not match: its `::` follows a word.
LEADING_COLON = /(?<![\w:])::([A-Z]\w*)/
DECLARATION = /\A\s*(?:class|module|interface)\s+(::)?(_?[A-Z]\w*(?:::_?[A-Z]\w*)*)/
# A keyword argument named `end:` must not close a declaration.
END_OF_DECLARATION = /\A\s*end\s*(?:#.*)?\z/

def prefixes(name)
  parts = name.split("::")
  (1..parts.size).map { |size| parts.first(size).join("::") }
end

# Yields each line with the namespaces visible from it. A declaration line sees
# its own namespace, because `class Datadog::Core::Logger < ::Logger` would
# otherwise inherit from itself.
def walk(lines)
  stack = []
  lines.each_with_index do |line, index|
    if (match = line.match(DECLARATION))
      full_name = match[1] ? match[2] : [stack.last, match[2]].compact.join("::")
      stack.push(full_name)
      yield index + 1, line, stack.flat_map { |name| prefixes(name) }, full_name
    else
      yield index + 1, line, stack.flat_map { |name| prefixes(name) }, nil
      stack.pop if line.match?(END_OF_DECLARATION)
    end
  end
end

def declared_names(files)
  names = {}
  files.each do |lines|
    walk(lines) { |_number, _line, _scope, full_name| names[full_name] = true if full_name }
  end
  names
end

def findings_for(path, lines, added, declared)
  findings = []
  walk(lines) do |number, line, scope, _full_name|
    next unless added.include?(number)
    next if line.lstrip.start_with?("#")

    line.scan(LEADING_COLON).flatten.each do |name|
      next unless FLAGGED_NAMES.include?(name)
      next if scope.any? { |namespace| declared.key?("#{namespace}::#{name}") }

      advice = if name == "Datadog"
        "Write the module relative to the enclosing namespace, for example `Core::Logger`."
      else
        "Write `#{name}`."
      end
      findings << "#{path}:#{number}: `::#{name}` has a leading `::`. #{advice} " \
        "Keep the `::` only where an enclosing namespace declares its own `#{name}`."
    end
  end
  findings
end

# Maps each changed file to the line numbers `git diff -U0` reports as added.
def parse_added_lines(diff)
  added = Hash.new { |hash, path| hash[path] = {} }
  path = nil
  diff.each_line do |line|
    if (match = line.match(%r{\A\+\+\+ b/(.+?)\s*\z}))
      path = match[1]
    elsif (match = line.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/))
      first = match[1].to_i
      count = (match[2] || "1").to_i
      count.times { |offset| added[path][first + offset] = true }
    end
  end
  added
end

def git(*args)
  Open3.capture3("git", "-c", "core.quotepath=off", "-c", "safe.directory=*", *args)
end

# Pull request checkouts are shallow, so a merge base needs more history than
# they carry. Fetching is a no-op on a full clone. Any failure aborts instead of
# passing, because a check that compared nothing would report success.
HISTORY_DEPTH = 200

def fetch_history(base_ref)
  _out, error, status = git(
    "fetch", "--no-tags", "--depth=#{HISTORY_DEPTH}", "origin", "+refs/heads/#{base_ref}:refs/remotes/origin/#{base_ref}"
  )
  abort("Could not fetch origin/#{base_ref}, so nothing was checked: #{error}") unless status.success?

  shallow, _err, _status = git("rev-parse", "--is-shallow-repository")
  return unless shallow.strip == "true"

  _out, error, status = git("fetch", "--no-tags", "--deepen=#{HISTORY_DEPTH}", "origin")
  abort("Could not deepen the checkout, so nothing was checked: #{error}") unless status.success?
end

# Compares against the merge base, so changes that landed on the base branch
# after this branch started are not mistaken for additions.
def comparison_point(base_ref)
  merge_base, _err, status = git("merge-base", "origin/#{base_ref}", "HEAD")
  return merge_base.strip if status.success?

  fetch_history(base_ref)
  merge_base, error, status = git("merge-base", "origin/#{base_ref}", "HEAD")
  abort("No merge base with origin/#{base_ref}, so nothing was checked: #{error}") unless status.success?

  merge_base.strip
end

def changed_signatures(base_ref)
  diff, error, status = git(
    "diff", "-U0", "-M", "--diff-filter=AMR", comparison_point(base_ref), "HEAD", "--", "sig/*.rbs"
  )
  abort("git diff against origin/#{base_ref} failed, so nothing was checked: #{error}") unless status.success?

  parse_added_lines(diff)
end

def self_test
  failed = 0
  total = 0
  check = lambda do |name, actual, expected|
    total += 1
    next if actual == expected

    puts "self-test failed: #{name}: expected #{expected.inspect}, got #{actual.inspect}"
    failed += 1
  end

  scan = lambda do |source, extra_declared = [], only: nil|
    lines = source.lines
    added = (only || (1..lines.size)).to_h { |number| [number, true] }
    declared = declared_names([lines] + extra_declared.map(&:lines))
    findings_for("sig/x.rbs", lines, added, declared).map { |finding| finding[/`::(\w+)`/, 1] }
  end

  check.call("plain names pass", scan.call("module Datadog\n  def a: (String) -> Hash[Symbol, Integer]\nend\n"), [])
  check.call("rooted core class fails", scan.call("module Datadog\n  def a: (::String) -> void\nend\n"), ["String"])
  check.call(
    "every rooted name on a line is reported",
    scan.call("module Datadog\n  def a: (::Hash[::Symbol, ::Integer]) -> void\nend\n"),
    %w[Hash Symbol Integer],
  )
  check.call(
    "nilable, optional and union forms fail",
    scan.call("module Datadog\n  def a: (?::Hash h, ::String | ::Integer) -> ::Float?\nend\n"),
    %w[Hash String Integer Float],
  )
  check.call("namespace separator is not a leading ::", scan.call("module Datadog\n  def a: (Foo::String, Core::Hash) -> void\nend\n"), [])
  check.call("rooted library namespace fails", scan.call("module Datadog\n  def a: () -> ::Datadog::Core::Logger\nend\n"), ["Datadog"])
  check.call(
    "third-party and standard-library names pass",
    scan.call("module Datadog\n  def a: (::Rack::Request, ::Logger, ::OpenFeature::SDK::Client) -> void\nend\n"),
    [],
  )
  check.call("comment lines pass", scan.call("module Datadog\n  # takes a ::String\nend\n"), [])
  check.call("only added lines are checked", scan.call("module Datadog\n  def a: (::String) -> void\n  def b: (::Hash) -> void\nend\n", only: [3]), ["Hash"])
  check.call("untouched lines pass", scan.call("module Datadog\n  def a: (::String) -> void\nend\n", only: [1]), [])

  shadowing = "module Datadog\n  module Core\n    module Utils\n      module Hash\n      end\n\n      def a: (::Hash h) -> void\n    end\n  end\nend\n"
  check.call("shadowed name passes inside the shadowing namespace", scan.call(shadowing), [])
  sibling = "module Datadog\n  module Tracing\n    def a: (::Hash h) -> void\n  end\nend\n"
  check.call(
    "shadow declared in another file does not excuse a sibling namespace",
    scan.call(sibling, [shadowing]),
    ["Hash"],
  )
  check.call(
    "shadow declared in another file excuses its own namespace",
    scan.call("module Datadog\n  module Core\n    module Utils\n      def a: (::Hash h) -> void\n    end\n  end\nend\n", [shadowing]),
    [],
  )
  check.call(
    "a keyword argument named end does not close the namespace",
    scan.call("module Datadog\n  module Core\n    module Utils\n      module Hash\n      end\n\n      def a: (\n        end: Integer,\n        ::Hash h\n      ) -> void\n    end\n  end\nend\n"),
    [],
  )
  check.call(
    "a closed namespace stops shadowing",
    scan.call("module Datadog\n  module Core\n    module Utils\n      module Hash\n      end\n    end\n\n    def a: (::Hash h) -> void\n  end\nend\n"),
    ["Hash"],
  )
  check.call(
    "own declaration shadows its superclass on the header line",
    scan.call("module Datadog\n  module Core\n    module Utils\n      class Time < ::Time\n      end\n    end\n  end\nend\n"),
    [],
  )
  check.call(
    "compact declaration shadows its superclass on the header line",
    scan.call("class Datadog::Core::Utils::Time < ::Time\nend\n"),
    [],
  )
  check.call("rooted superclass without a clash fails", scan.call("class Datadog::Foo < ::StandardError\nend\n"), ["StandardError"])
  check.call("interfaces are tracked", scan.call("module Datadog\n  interface _Reader\n    def a: (::String) -> void\n  end\nend\n"), ["String"])

  diff = <<~DIFF
    diff --git a/sig/a.rbs b/sig/a.rbs
    --- a/sig/a.rbs
    +++ b/sig/a.rbs
    @@ -3,0 +4,2 @@ module Datadog
    +  def a: () -> void
    +  def b: () -> void
    @@ -9 +11 @@ module Datadog
    -  def c: () -> void
    +  def c: (Integer) -> void
    @@ -20,2 +21,0 @@ module Datadog
    -  def d: () -> void
    -  def e: () -> void
    diff --git a/sig/b.rbs b/sig/b.rbs
    --- a/sig/b.rbs
    +++ b/sig/b.rbs
    @@ -0,0 +1,3 @@
    +module B
    +end
    +
  DIFF
  expected = {"sig/a.rbs" => [4, 5, 11], "sig/b.rbs" => [1, 2, 3]}
  check.call("diff hunks map to added line numbers", parse_added_lines(diff).transform_values { |lines| lines.keys.sort }, expected)

  abort("self-test: #{failed} of #{total} cases failed") if failed > 0
  puts "self-test OK: #{total} cases"
end

if ARGV.first == "--self-test"
  self_test
  exit
end

base_ref = ENV["BASE_REF"].to_s
base_ref = ENV["GITHUB_BASE_REF"].to_s if base_ref.empty?
if base_ref.empty?
  puts "RBS leading :: check skipped: no BASE_REF or GITHUB_BASE_REF, so there is nothing to compare against"
  exit
end

changed = changed_signatures(base_ref)
declared = declared_names(Dir.glob("sig/**/*.rbs").sort.map { |path| File.readlines(path) })
findings = changed.flat_map do |path, added|
  findings_for(path, File.readlines(path), added, declared)
end

if findings.empty?
  puts "RBS leading :: check OK (#{changed.size} changed signature files)"
  exit
end

claim = "RBS signatures: added lines have a leading `::` on a core class or on Datadog."
fix = "Fix: drop the leading `::`, see .agents/skills/write-rbs/SKILL.md."
if ENV["GITHUB_ACTIONS"] == "true"
  findings.each { |finding| puts "::error ::#{finding}" }
  puts "::error ::#{claim} #{fix}"
else
  puts claim
  puts fix
  puts ""
  findings.each { |finding| puts " - #{finding}" }
end
exit 1
