# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

# Fetches the canonical FFE fixture corpus from DataDog/ffe-system-test-data
# into a SHA-keyed cache under tmp/. Only the pin file beside this class
# lives in the repo. The update-ffe-fixtures workflow rewrites it.
# It mirrors update-system-tests.
class FfeFixtures
  SOURCE_REPOSITORY = "DataDog/ffe-system-test-data"
  COMMIT_SHA = File.read(File.expand_path("ffe/version", __dir__)).strip
  raise "ffe/version must contain one full commit SHA" unless COMMIT_SHA.match?(/\A[0-9a-f]{40}\z/)

  CACHE = File.join("tmp", "ffe-system-test-data")
  CASES_PATTERN = %r{\Aevaluation-cases/[^/]+\.json\z}.freeze

  def self.download(repository_root, sha: COMMIT_SHA)
    new(repository_root, sha).download
  end

  def initialize(repository_root, sha)
    @repository_root = repository_root
    @sha = sha
  end

  def download
    cache = File.join(@repository_root, CACHE, @sha)
    return cache if File.directory?(cache)

    staging = File.join(@repository_root, CACHE, ".partial-#{@sha}")
    FileUtils.rm_rf(staging)
    fixture_paths.each do |path|
      destination = File.join(staging, path)
      FileUtils.mkdir_p(File.dirname(destination))
      File.binwrite(destination, http_get(raw_url(path)))
    end
    begin
      File.rename(staging, cache)
    rescue Errno::ENOTEMPTY, Errno::EEXIST
      FileUtils.rm_rf(staging)
    end
    cache
  end

  private

  def fixture_paths
    tree = JSON.parse(http_get(tree_url)).fetch("tree")
    tree.select { |entry| entry["type"] == "blob" }.map { |entry| entry["path"] }
      .select { |path| path == "ufc-config.json" || path.match?(CASES_PATTERN) }
  end

  def tree_url
    "https://api.github.com/repos/#{SOURCE_REPOSITORY}/git/trees/#{@sha}?recursive=1"
  end

  def raw_url(path)
    "https://raw.githubusercontent.com/#{SOURCE_REPOSITORY}/#{@sha}/#{path}"
  end

  def http_get(url)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "dd-trace-rb-ffe-fixtures"
      request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}" if ENV["GITHUB_TOKEN"]
      response = http.request(request)
      raise "GET #{url} failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  end
end
