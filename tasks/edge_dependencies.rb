require "bundler"
require "json"
require "net/http"
require "open3"
require "set"

# Gems that `edge:update` moves to their latest release, and the report of
# which of them moved, published in the "Update Latest Dependency" PR body.
#
# Loadable without the bundle (only bundler and the standard library), so the
# workflow can run it with `ruby -r./tasks/edge_dependencies`.
module EdgeDependencies
  # Naming convention:
  #
  # Key: integration name, the same as the name of spec task in Rakefile and MatrixFile
  # Value: gem name, or a list of gem names when the group bundles several that
  # the integration owns (e.g. ethon + typhoeus, or the aws-sdk family)
  ALLOWLIST = {
    "ai_guard:ruby_llm" => "ruby_llm",
    "appsec:active_record" => "activerecord",
    "appsec:devise" => "devise",
    "aws" => ["aws-sdk", "aws-sdk-core"],
    "dalli" => "dalli",
    "elasticsearch" => "elasticsearch",
    "ethon" => ["ethon", "typhoeus"],
    "excon" => "excon",
    "faraday" => ["faraday", "faraday-follow_redirects"],
    "grape" => "grape",
    "graphql" => "graphql",
    "grpc" => "grpc",
    "httpclient" => "httpclient",
    "httprb" => "http",
    "karafka" => "karafka",
    "mongodb" => "mongo",
    "open_feature" => "openfeature-sdk",
    "opensearch" => "opensearch-ruby",
    "rack" => "rack",
    "redis" => "redis",
    "rest_client" => "rest-client",
    "sequel" => "sequel",
    "shoryuken" => ["shoryuken", "aws-sdk-sqs"],
    "sneakers" => "kicks",
    "stripe" => "stripe",
    "waterdrop" => "waterdrop",
    # Add more integrations here, when their gems need to track the latest
    # release; the gems may live in a shared group, as long as each entry
    # lists only the gems that integration owns
  }.freeze

  # The heading and table header are parsed by tooling outside this repository
  # (the same format as dd-trace-dotnet's package bump PRs); keep them verbatim.
  HEADING = "## Package Version Updates"
  TABLE_HEADER = [
    "| Package | Integration | Previous | New | Published |",
    "| --- | --- | --- | --- | --- |",
  ].freeze
  NO_CHANGES = "No instrumented gem changed."
  NEW_GEM = "(new)"

  # "gemfiles/ruby_3.4_openfeature_latest.gemfile.lock" => "openfeature_latest".
  # Parent lockfiles ("ruby-3.4.gemfile.lock") have no group and never match.
  LOCKFILE_GROUP = /\A[a-z]+_\d+\.\d+_(.+)\.gemfile\.lock\z/

  Change = Struct.new(:gem, :integration, :previous, :new)

  module_function

  # Allowlisted gems whose locked version differs between two revisions.
  #
  # A gem counts for an integration only in that integration's own groups, so a
  # transitive move (faraday in an elasticsearch group) is not reported.
  #
  # matrix:    the evaluated Matrixfile
  # lockfiles: paths of the updated lockfiles
  # previous:  callable from a lockfile path to its previous content, or nil
  #            when the lockfile is new
  # current:   callable from a lockfile path to its updated content
  def changes(matrix:, lockfiles:, previous:, current: File.method(:read), allowlist: ALLOWLIST)
    owners = owners_by_group(matrix, allowlist)

    found = lockfiles.sort.flat_map do |path|
      group = File.basename(path)[LOCKFILE_GROUP, 1]
      next [] unless group && owners.key?(group)

      before = versions(previous.call(path))
      after = versions(current.call(path))

      # `filter_map` needs Ruby 2.7, and the tasks specs run from 2.5.
      owners.fetch(group).map do |integration, gem|
        next unless after.key?(gem)
        next if before[gem] == after[gem]

        Change.new(gem, integration, before[gem], after[gem])
      end.compact
    end

    found.uniq.sort_by do |change|
      [change.integration, change.gem, Gem::Version.new(change.new), change.previous.to_s]
    end
  end

  def markdown(changes, published: ->(_gem, _version) {})
    return "#{HEADING}\n\n#{NO_CHANGES}\n" if changes.empty?

    rows = changes.map do |change|
      cells = [
        change.gem,
        change.integration,
        change.previous || NEW_GEM,
        change.new,
        published.call(change.gem, change.new),
      ]
      "| #{cells.map(&:to_s).join(" | ")} |"
    end

    [HEADING, "", *TABLE_HEADER, *rows].join("\n") + "\n"
  end

  # Entry point for the workflow: compares gemfiles/ in the working tree with
  # `base` and returns the markdown section.
  def report(base: "HEAD", root: Dir.pwd, published: RubyGemsReleaseDates.new)
    Dir.chdir(root) do
      matrix = eval(File.read("Matrixfile", encoding: "UTF-8")).freeze # rubocop:disable Security/Eval
      lockfiles = Dir["gemfiles/*.gemfile.lock"]
      previous = ->(path) { git_show(base, path) }

      markdown(changes(matrix: matrix, lockfiles: lockfiles, previous: previous), published: published)
    end
  end

  # { "openfeature_latest" => [["open_feature", "openfeature-sdk"]], ... }
  def owners_by_group(matrix, allowlist)
    owners = Hash.new { |hash, key| hash[key] = [] }

    allowlist.each do |integration, gems|
      matrix.fetch(integration).each_key do |group|
        next if group.empty?

        Array(gems).each { |gem| owners[group.tr("-", "_")] << [integration, gem] }
      end
    end

    owners
  end

  # Platform variants of a gem share one version, so the name is enough.
  def versions(content)
    return {} if content.nil?

    Bundler::LockfileParser.new(content).specs.each_with_object({}) do |spec, result|
      result[spec.name] = spec.version.to_s
    end
  end

  def git_show(revision, path)
    output, status = Open3.capture2e("git", "show", "#{revision}:#{path}")
    status.success? ? output : nil
  end

  # Release dates from rubygems.org, one request per gem. Any failure leaves the
  # cell empty: the date is informational and must not fail the update.
  class RubyGemsReleaseDates
    ENDPOINT = "https://rubygems.org/api/v1/versions/%s.json"

    def initialize
      @releases = {}
    end

    def call(gem, version)
      release = releases(gem).find { |entry| entry["number"] == version && entry["platform"] == "ruby" } ||
        releases(gem).find { |entry| entry["number"] == version }
      release && release["created_at"].to_s[0, 10]
    end

    private

    def releases(gem)
      @releases[gem] ||= begin
        response = Net::HTTP.get_response(URI(format(ENDPOINT, gem)))
        response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : []
      rescue => e
        warn "Could not fetch release dates for #{gem}: #{e.class}: #{e.message}"
        []
      end
    end
  end
end
