# frozen_string_literal: true

require_relative "release_notes"

namespace :changelog do
  desc "Validate unreleased/*.json changelog fragments (schema only; message hygiene is checked by changelog:lint_messages)"
  task :lint do
    ReleaseNotes::Fragments.read_all
    ReleaseNotes::Fragments.validate_examples!
    puts "All unreleased/ changelog fragments are valid."
  rescue ReleaseNotes::Fragments::ValidationError => e
    abort "::error::#{e.message}"
  end

  desc "Render the pending unreleased/ changelog fragments as they would appear in CHANGELOG.md"
  task :render do
    entries = ReleaseNotes::Fragments.read_all
    highlights_path = "unreleased/highlights.md"
    highlights = File.exist?(highlights_path) ? File.read(highlights_path) : nil

    rendered = ReleaseNotes::Fragments.render(entries, highlights: highlights)
    puts rendered.empty? ? "(no pending changelog fragments)" : rendered
  end

  desc "Lint unreleased/ changelog fragment messages for hygiene with vale"
  task :lint_messages do
    require "tmpdir"

    entries = ReleaseNotes::Fragments.read_all
    next puts("No unreleased/ changelog fragments to lint.") if entries.empty?

    # Vale's markdown parsing does not preserve trailing whitespace, so no vale rule
    # can detect it; checked here instead.
    offenders = entries.select { |entry| /[ \t]\z/.match?(entry.fetch("message")) }
    unless offenders.empty?
      abort "::error::Changelog message has trailing whitespace: #{offenders.map { |e| e.fetch("_path") }.join(", ")}"
    end

    Dir.mktmpdir do |dir|
      entries.each_with_index do |entry, index|
        File.write(File.join(dir, "#{index}.md"), entry.fetch("message"))
      end

      sh "vale --config=#{File.expand_path(".vale.ini")} #{dir}"
    end
  end
end
