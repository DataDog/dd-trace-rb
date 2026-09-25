require_relative "appraisal_conversion"

class GithubMatrix
  # TODO: These are the execptions, find a way to describe those service dependencies in CI using a more generic mechansim.
  MISC_CANDIDATES = %w[
    mongodb
    elasticsearch
    opensearch
    presto
    dalli
  ].freeze

  attr_reader :ruby_version

  def initialize(matrix_path: "Matrixfile", ruby_version: RUBY_VERSION[0..2], gemfile_resolver: nil)
    @matrix_path = matrix_path
    @ruby_version = ruby_version
    @gemfile_resolver = gemfile_resolver || AppraisalConversion.method(:to_bundle_gemfile)
  end

  def tasks
    @tasks ||= matching_entries.map do |key, group|
      {
        task: key,
        group: group,
        gemfile: resolve_gemfile(group),
      }
    end
  end

  def standard_tasks
    tasks.reject { |task| MISC_CANDIDATES.include?(task[:task]) }
  end

  def misc_tasks
    tasks.select { |task| MISC_CANDIDATES.include?(task[:task]) }
  end

  def appraisal_gemfiles
    tasks.map { |task| task[:gemfile] }.reject { |path| path == "Gemfile" }.uniq.sort
  end

  private

  def matching_entries
    matrix.each_with_object([]) do |(key, spec_metadata), entries|
      spec_metadata.each do |group, rubies|
        entries << [key, group] if rubies.include?("✅ #{ruby_version}")
      end
    end
  end

  def matrix
    @matrix ||= eval(File.read(@matrix_path), binding, @matrix_path).freeze # rubocop:disable Security/Eval
  end

  def resolve_gemfile(group)
    @gemfile_resolver.call(group)
  rescue
    "Gemfile"
  end
end
