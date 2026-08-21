require "spec_helper"
require "appraisal/appraisal"
require_relative "../../appraisal/source_options"

# `appraisal/generate.rb` patches Appraisal's DSL so a supply-chain cooldown
# window can be declared on the `source` line of every generated gemfile.
# Appraisal owns that rendering, so these specs pin the behaviour we depend on:
# an upstream change that drops the options would otherwise silently disable
# cooldown across all generated gemfiles.
RSpec.describe "Appraisal source cooldown rendering" do
  subject(:gemfile) { Appraisal::Gemfile.new }

  def rendered_source(gemfile)
    gemfile.to_s.lines.first.to_s.strip
  end

  it "renders a bare source line when no options are given" do
    gemfile.source("https://rubygems.org")

    expect(rendered_source(gemfile)).to eq('source "https://rubygems.org"')
  end

  it "renders options alongside the source url" do
    gemfile.source("https://rubygems.org", cooldown: 2)

    expect(rendered_source(gemfile)).to eq('source "https://rubygems.org", cooldown: 2')
  end

  # `Gemfile#dup` builds a fresh object and replays through the
  # `source_entry_for_dup` alias, which is bound at class-definition time.
  # Appraisal dups the gemfile for every appraisal, so options must survive it.
  it "preserves options across dup" do
    gemfile.source("https://rubygems.org", cooldown: 2)

    expect(rendered_source(gemfile.dup)).to eq('source "https://rubygems.org", cooldown: 2')
  end

  it "keeps supporting source blocks" do
    gemfile.source("https://rubygems.org") do
      gem "rake"
    end

    expect(gemfile.to_s).to include("rake")
  end
end
