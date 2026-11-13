require "spec_helper"
require_relative "../../tasks/edge_dependencies"

RSpec.describe EdgeDependencies do
  def lockfile(specs)
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
      #{specs.map { |name, version| "    #{name} (#{version})" }.join("\n")}

      PLATFORMS
        ruby

      DEPENDENCIES
      #{specs.keys.map { |name| "  #{name}" }.join("\n")}

      BUNDLED WITH
         2.3.26
    LOCKFILE
  end

  let(:matrix) do
    {
      "open_feature" => {"openfeature-latest" => "✅ 3.4", "openfeature-min" => "✅ 3.4"},
      "dalli" => {"dalli-latest" => "✅ 3.4"},
      "faraday" => {"faraday-latest" => "✅ 3.4"},
      "elasticsearch" => {"elasticsearch-latest" => "✅ 3.4"},
    }
  end

  let(:allowlist) do
    {
      "open_feature" => "openfeature-sdk",
      "dalli" => "dalli",
      "faraday" => "faraday",
      "elasticsearch" => "elasticsearch",
    }
  end

  let(:before) { {} }
  let(:after) { {} }

  subject(:changes) do
    described_class.changes(
      matrix: matrix,
      lockfiles: after.keys,
      previous: ->(path) { before[path] && lockfile(before[path]) },
      current: ->(path) { lockfile(after[path]) },
      allowlist: allowlist,
    )
  end

  describe ".changes" do
    context "when an allowlisted gem moves in its integration's group" do
      let(:before) { {"gemfiles/ruby_3.4_openfeature_latest.gemfile.lock" => {"openfeature-sdk" => "0.6.5", "json" => "2.0.0"}} }
      let(:after) { {"gemfiles/ruby_3.4_openfeature_latest.gemfile.lock" => {"openfeature-sdk" => "0.8.1", "json" => "3.0.0"}} }

      it "reports the gem with its integration, and not the transitive gem" do
        expect(changes.map(&:to_a)).to eq([["openfeature-sdk", "open_feature", "0.6.5", "0.8.1"]])
      end
    end

    context "when the same move appears on several Ruby versions" do
      let(:before) do
        {
          "gemfiles/ruby_3.3_dalli_latest.gemfile.lock" => {"dalli" => "5.1.1"},
          "gemfiles/ruby_3.4_dalli_latest.gemfile.lock" => {"dalli" => "5.1.1"},
          "gemfiles/ruby_2.7_dalli_latest.gemfile.lock" => {"dalli" => "3.2.10"},
        }
      end
      let(:after) do
        {
          "gemfiles/ruby_3.3_dalli_latest.gemfile.lock" => {"dalli" => "5.2.5"},
          "gemfiles/ruby_3.4_dalli_latest.gemfile.lock" => {"dalli" => "5.2.5"},
          "gemfiles/ruby_2.7_dalli_latest.gemfile.lock" => {"dalli" => "3.2.15"},
        }
      end

      it "collapses repeated moves and keeps each release track" do
        expect(changes.map(&:to_a)).to eq(
          [
            ["dalli", "dalli", "3.2.10", "3.2.15"],
            ["dalli", "dalli", "5.1.1", "5.2.5"],
          ],
        )
      end
    end

    context "when an allowlisted gem moves in another integration's group" do
      let(:before) { {"gemfiles/ruby_3.4_elasticsearch_latest.gemfile.lock" => {"elasticsearch" => "9.5.0", "faraday" => "2.14.4"}} }
      let(:after) { {"gemfiles/ruby_3.4_elasticsearch_latest.gemfile.lock" => {"elasticsearch" => "9.5.0", "faraday" => "2.15.1"}} }

      it "does not report it" do
        expect(changes).to be_empty
      end
    end

    context "when a parent lockfile changes" do
      let(:before) { {"gemfiles/ruby-3.4.gemfile.lock" => {"faraday" => "2.14.4"}} }
      let(:after) { {"gemfiles/ruby-3.4.gemfile.lock" => {"faraday" => "2.15.1"}} }

      it "does not report it" do
        expect(changes).to be_empty
      end
    end

    context "when the lockfile is new" do
      let(:after) { {"gemfiles/ruby_3.4_faraday_latest.gemfile.lock" => {"faraday" => "2.15.1"}} }

      it "reports the gem without a previous version" do
        expect(changes.map(&:to_a)).to eq([["faraday", "faraday", nil, "2.15.1"]])
      end
    end
  end

  describe ".markdown" do
    it "renders one row per change under the fixed heading" do
      changes = [
        described_class::Change.new("openfeature-sdk", "open_feature", "0.6.5", "0.8.1"),
        described_class::Change.new("faraday", "faraday", nil, "2.15.1"),
      ]
      published = ->(gem, _version) { (gem == "openfeature-sdk") ? "2026-10-23" : nil }

      expect(described_class.markdown(changes, published: published)).to eq(<<~MARKDOWN)
        ## Package Version Updates

        | Package | Integration | Previous | New | Published |
        | --- | --- | --- | --- | --- |
        | openfeature-sdk | open_feature | 0.6.5 | 0.8.1 | 2026-10-23 |
        | faraday | faraday | (new) | 2.15.1 |  |
      MARKDOWN
    end

    it "says so when no instrumented gem changed" do
      expect(described_class.markdown([])).to eq("## Package Version Updates\n\nNo instrumented gem changed.\n")
    end
  end

  describe "::ALLOWLIST" do
    it "only names integrations that the Matrixfile defines" do
      matrix = eval(File.read("Matrixfile", encoding: "UTF-8")) # rubocop:disable Security/Eval

      expect(described_class::ALLOWLIST.keys - matrix.keys).to be_empty
    end
  end
end
