# frozen_string_literal: true

require_relative "release_prep"

namespace :changelog do
  desc "Validate unreleased/*.json changelog fragments (schema only; message hygiene is checked by changelog:lint_messages)"
  task :lint do
    ReleasePrep::Fragments.read_all
    ReleasePrep::Fragments.read_examples
    puts "All unreleased/ changelog fragments are valid."
  rescue ReleasePrep::ValidationError => e
    ReleasePrep.fail!(e.message)
  end

  desc "Render the pending unreleased/ changelog fragments as they would appear in CHANGELOG.md"
  task :render do
    highlights_path = "unreleased/highlights.md"
    highlights = File.exist?(highlights_path) ? File.read(highlights_path) : nil

    rendered = ReleasePrep::Fragments.read_all.render(highlights: highlights)
    puts rendered.empty? ? "(no pending changelog fragments)" : rendered
  end

  desc "Lint unreleased/ changelog fragment messages for hygiene with vale"
  task :lint_messages do
    require "tmpdir"

    fragments = ReleasePrep::Fragments.read_all
    next puts("No unreleased/ changelog fragments to lint.") if fragments.empty?

    # Vale's markdown parsing does not preserve trailing whitespace, so no vale rule
    # can detect it; checked here instead.
    offenders = fragments.select { |fragment| /[ \t]\z/.match?(fragment.message) }
    unless offenders.empty?
      ReleasePrep.fail!("Changelog message has trailing whitespace: #{offenders.map(&:path).join(", ")}")
    end

    Dir.mktmpdir do |dir|
      fragments.each_with_index do |fragment, index|
        File.write(File.join(dir, "#{index}.md"), fragment.message)
      end

      sh "vale --config=#{File.expand_path(".vale.ini")} #{dir}"
    end
  end
end
