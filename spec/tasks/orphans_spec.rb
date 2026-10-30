require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../tasks/appraisal_conversion"

# The script resolves `appraisal/`, `gemfiles/` and `Matrixfile` against its
# working directory and exits at top level, so each example executes it in a
# subprocess rooted at a throwaway gemfile tree.
RSpec.describe "appraisal/orphans.rb" do
  let(:tree_dir) { Dir.mktmpdir }
  let(:runtime_identifier) { AppraisalConversion.runtime_identifier }
  let(:runtime_prefix) { "#{runtime_identifier.tr("-", "_")}_" }
  let(:ruby_column) { runtime_identifier.delete_prefix("ruby-") }
  let(:definition_path) { File.join(tree_dir, "appraisal", "#{runtime_identifier}.rb") }
  let(:orphans_script_path) { File.expand_path("../../appraisal/orphans.rb", __dir__) }

  after { FileUtils.remove_entry(tree_dir) }

  def write_definition(group)
    FileUtils.mkdir_p(File.dirname(definition_path))
    File.write(definition_path, <<~RUBY)
      appraise '#{group}' do
        gem '#{group}'
      end
    RUBY
  end

  def write_gemfiles(*names)
    FileUtils.mkdir_p(File.join(tree_dir, "gemfiles"))
    names.each do |name|
      File.write(File.join(tree_dir, "gemfiles", name), "")
      File.write(File.join(tree_dir, "gemfiles", "#{name}.lock"), "")
    end
  end

  def write_orphaned_lockfile(name)
    FileUtils.mkdir_p(File.join(tree_dir, "gemfiles"))
    File.write(File.join(tree_dir, "gemfiles", name), "")
  end

  def write_matrixfile(active_groups)
    File.write(File.join(tree_dir, "Matrixfile"), "#{active_groups.inspect}.freeze\n")
  end

  def write_matrixfile_raising_on_evaluation
    File.write(File.join(tree_dir, "Matrixfile"), 'raise "Matrixfile was evaluated"\n')
  end

  def run_orphans_script
    # The tree is named for the running process's runtime identifier, so the
    # subprocess must be this ruby; clearing the inherited bundler environment
    # keeps it from activating a bundle whose Gemfile does not resolve from
    # the throwaway tree.
    Open3.capture2e(
      {"RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil},
      Gem.ruby, orphans_script_path,
      chdir: tree_dir,
    )
  end

  context "when every gemfile has a definition and every lockfile has a gemfile" do
    before do
      write_definition("defined")
      write_gemfiles("#{runtime_prefix}defined.gemfile")
      write_matrixfile_raising_on_evaluation
    end

    it "exits 0 silently" do
      out, status = run_orphans_script

      expect(out).to be_empty
      expect(status.exitstatus).to eq(0)
    end
  end

  context "when a lockfile has no corresponding gemfile" do
    before do
      write_definition("defined")
      write_gemfiles("#{runtime_prefix}defined.gemfile")
      write_orphaned_lockfile("#{runtime_prefix}ghost.gemfile.lock")
      write_matrixfile_raising_on_evaluation
    end

    it "warns to delete the lockfile and exits 1 without reading Matrixfile" do
      out, status = run_orphans_script

      expect(out).to eq(
        "gemfiles/#{runtime_prefix}ghost.gemfile.lock has no corresponding " \
        "gemfiles/#{runtime_prefix}ghost.gemfile; delete the lockfile.\n"
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  context "when a gemfile has no matching appraise definition" do
    before do
      write_definition("defined")
      write_gemfiles("#{runtime_prefix}defined.gemfile", "#{runtime_prefix}extra.gemfile")
      write_matrixfile("example_task" => {"extra" => "✅ #{ruby_column}"})
    end

    it "warns from the Matrixfile coverage and exits 1" do
      out, status = run_orphans_script

      expect(out).to eq(
        "#{runtime_prefix}extra.gemfile has no `appraise 'extra'` block in #{definition_path}, " \
        "but Matrixfile marks it active for Ruby #{ruby_column}. Add the missing `appraise` block.\n"
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  context "when a gemfile and a lockfile are both orphaned" do
    before do
      write_definition("defined")
      write_gemfiles("#{runtime_prefix}defined.gemfile", "#{runtime_prefix}extra.gemfile")
      write_orphaned_lockfile("#{runtime_prefix}ghost.gemfile.lock")
      write_matrixfile("example_task" => {"extra" => "✅ #{ruby_column}"})
    end

    it "warns for both orphan kinds and exits 1" do
      out, status = run_orphans_script

      expect(out).to eq(
        "#{runtime_prefix}extra.gemfile has no `appraise 'extra'` block in #{definition_path}, " \
        "but Matrixfile marks it active for Ruby #{ruby_column}. Add the missing `appraise` block.\n" \
        "gemfiles/#{runtime_prefix}ghost.gemfile.lock has no corresponding " \
        "gemfiles/#{runtime_prefix}ghost.gemfile; delete the lockfile.\n"
      )
      expect(status.exitstatus).to eq(1)
    end
  end
end
