# frozen_string_literal: true

# Denies edits to files matching <pattern> unless <skill> was loaded
# in the current session
#
# @hook PreToolUse
#
# Examples:
#
#   Wire as a PreToolUse hook; reads the tool payload JSON on stdin
#   ruby require-skill.rb write-rbs 'sig/.*\.rbs$|vendor/rbs/.*\.rbs$'
#
#   Run the inline test suite
#   TEST=1 ruby require-skill.rb
#
# Emits a PreToolUse "deny" decision (exit 0 + JSON) when the skill is absent

require "json"

class Skill
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def loaded?(transcript_path)
    path = transcript_path.to_s
    return false if path.empty? || !File.exist?(path)

    File.foreach(path).any? { |line| invoked?(line) }
  end

  private

  def invoked?(line)
    message = JSON.parse(line)["message"]
    content = message.is_a?(Hash) ? message["content"] : nil
    return false unless content.is_a?(Array)

    content.any? do |item|
      item.is_a?(Hash) &&
        item["type"] == "tool_use" &&
        item["name"] == "Skill" &&
        item["input"].is_a?(Hash) &&
        item["input"]["skill"] == @name
    end
  rescue JSON::ParserError
    false
  end
end

class Runner
  def initialize(argv)
    @skill = Skill.new(argv[0])
    @guarded_path_pattern = Regexp.new(argv[1])
  end

  def run(input)
    payload = JSON.parse(input)
    file_path = payload.fetch("tool_input", {}).fetch("file_path", "").to_s

    exit(0) if file_path.empty? || !@guarded_path_pattern.match?(file_path)
    exit(0) if @skill.loaded?(payload["transcript_path"])

    reason = "Editing #{file_path} requires the /#{@skill.name} skill. Load it first, then retry."
    puts JSON.generate(
      "hookSpecificOutput" => {
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => reason,
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

  def skill_event(name)
    JSON.generate(
      "message" => {
        "content" => [
          {"type" => "tool_use", "name" => "Skill", "input" => {"skill" => name}},
        ],
      },
    ) + "\n"
  end

  def test_loaded_when_skill_invoked
    transcript(skill_event("write-rbs")) do |path|
      assert skill.loaded?(path)
    end
  end

  def test_not_loaded_when_absent
    transcript("nothing relevant here\n") do |path|
      refute skill.loaded?(path)
    end
  end

  def test_mention_in_prose_does_not_satisfy_requirement
    transcript(%({"message":{"content":[{"type":"text","text":"use the write-rbs skill"}]}}\n)) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_prefixed_skill_name_does_not_satisfy_requirement
    transcript(skill_event("something-write-rbs")) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_suffixed_skill_name_does_not_satisfy_requirement
    transcript(skill_event("write-rbs-something")) do |path|
      refute skill.loaded?(path)
    end
  end

  def test_not_loaded_when_transcript_missing
    refute skill.loaded?("/no/such")
    refute skill.loaded?(nil)
  end
end
