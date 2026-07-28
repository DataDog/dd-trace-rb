# frozen_string_literal: true

# PreToolUse guard: deny edits to files matching <pattern> unless <skill> was
# loaded in the current session.
#
#   Hook:  ruby require-skill.rb <skill> <pattern>   (payload JSON on stdin)
#   Tests: TEST=1 ruby require-skill.rb
#
# Emits a PreToolUse "deny" decision (exit 0 + JSON) when the skill is absent.

require "json"

class Skill
  def initialize(name)
    @name = name
    @marker = /(?<![\w-])#{Regexp.escape(name)}(?![\w-])/
  end

  def loaded?(transcript_path)
    path = transcript_path.to_s
    return false if path.empty? || !File.exist?(path)

    File.foreach(path).any? { |line| @marker.match?(line) }
  end
end

class Runner
  def initialize(argv)
    @skill = argv[0]
    @guarded_path_pattern = Regexp.new(argv[1])
  end

  def run(input)
    payload = JSON.parse(input)
    file_path = payload.fetch("tool_input", {}).fetch("file_path", "").to_s

    exit(0) if file_path.empty? || !@guarded_path_pattern.match?(file_path)
    exit(0) if Skill.new(@skill).loaded?(payload["transcript_path"])

    puts JSON.generate(
      "hookSpecificOutput" => {
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => "Editing #{file_path} requires the /#{@skill} skill. Load it first, then retry.",
      },
    )
    exit(0)
  rescue => e
    # NOTE: This is a fail-open handling with re-surfacing error to developer
    puts JSON.generate("systemMessage" => "[require-skill] #{e.class}: #{e.message}")

    exit(0)
  end
end

Runner.new(ARGV).run($stdin.read) unless ENV["TEST"] == "1"

# ==============================================================================
# Tests — run with: TEST=1 ruby require-skill.rb
# ==============================================================================

require "tempfile"
require "test/unit"

class SkillTest < Test::Unit::TestCase
  def skill
    Skill.new("write-rbs")
  end

  def transcript(contents)
    file = Tempfile.new("transcript")
    file.write(contents)
    file.close
    yield file.path
  ensure
    file&.unlink
  end

  def test_loaded_when_skill_present
    transcript(%({"role":"user","content":"<command-name>write-rbs</command-name>"}\n)) do |path|
      assert skill.loaded?(path)
    end
  end

  def test_not_loaded_when_absent
    transcript("nothing relevant here\n") do |path|
      refute skill.loaded?(path)
    end
  end

  def test_prefixed_skill_name_does_not_satisfy_requirement
    transcript(%({"content":"loaded local-write-rbs skill"}\n)) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_suffixed_skill_name_does_not_satisfy_requirement
    transcript(%({"content":"loaded write-rbs-legacy skill"}\n)) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_not_loaded_when_transcript_missing
    refute skill.loaded?("/no/such")
    refute skill.loaded?(nil)
  end
end
