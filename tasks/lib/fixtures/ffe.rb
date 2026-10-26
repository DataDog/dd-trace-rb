# frozen_string_literal: true

require "fileutils"
require "net/http"
require "stringio"
require "uri"
require "zlib"
require "rubygems/package"

# Downloads the canonical FFE fixture corpus from DataDog/ffe-system-test-data
# into a SHA-keyed cache under tmp/. Only the pin file beside this class
# lives in the repo. The update-ffe-fixtures workflow rewrites it.
# It mirrors update-system-tests.
class FfeFixtures
  SOURCE_REPOSITORY = "DataDog/ffe-system-test-data"
  COMMIT_SHA = File.read(File.expand_path("ffe/version", __dir__)).strip
  raise "ffe/version must contain one full commit SHA" unless COMMIT_SHA.match?(/\A[0-9a-f]{40}\z/)

  CACHE = File.join("tmp", "ffe-system-test-data")
  CASES_PATTERN = %r{\Aevaluation-cases/[^/]+\.json\z}.freeze
  HTTP_ATTEMPTS = 3
  HTTP_TIMEOUT_SECONDS = 15
  RETRYABLE_STATUS = /\A(429|5\d\d)\z/.freeze
  HTTP_TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, EOFError, SocketError, SystemCallError].freeze

  class TransientHTTPError < StandardError
  end

  def self.download(repository_root, sha: COMMIT_SHA)
    new(repository_root, sha).download
  end

  def self.applicable?(test_case, platform:)
    return false if test_case.fetch("_skip", []).any? { |entry| entry.fetch("platform") == platform }

    !test_case.key?("_include") || test_case.fetch("_include").any? { |entry| entry.fetch("platform") == platform }
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
    extract(http_get(tarball_url), staging)
    unless File.file?(File.join(staging, "ufc-config.json")) && Dir[File.join(staging, "evaluation-cases", "*.json")].any?
      raise "No FFE fixtures found at #{tarball_url}"
    end
    begin
      File.rename(staging, cache)
    rescue Errno::ENOTEMPTY, Errno::EEXIST
      FileUtils.rm_rf(staging)
    end
    cache
  end

  private

  def extract(gzip, staging)
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(gzip))) do |tar|
      tar.each do |entry|
        relative = entry.full_name.sub(/\A[^\/]+\//, "")
        next unless relative == "ufc-config.json" || relative.match?(CASES_PATTERN)

        destination = File.join(staging, relative)
        FileUtils.mkdir_p(File.dirname(destination))
        File.binwrite(destination, entry.read)
      end
    end
  end

  def tarball_url
    "https://codeload.github.com/#{SOURCE_REPOSITORY}/tar.gz/#{@sha}"
  end

  def http_get(url)
    attempts = 0
    begin
      attempts += 1
      http_attempt(url)
    rescue TransientHTTPError, *HTTP_TRANSIENT_ERRORS
      raise if attempts >= HTTP_ATTEMPTS

      sleep(attempts)
      retry
    end
  end

  def http_attempt(url)
    uri = URI(url)
    Net::HTTP.start(
      uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: HTTP_TIMEOUT_SECONDS, read_timeout: HTTP_TIMEOUT_SECONDS
    ) do |http|
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "dd-trace-rb-ffe-fixtures"
      request["Authorization"] = "Bearer #{ENV["GITHUB_TOKEN"]}" if ENV["GITHUB_TOKEN"]
      response = http.request(request)
      return response.body if response.is_a?(Net::HTTPSuccess)
      raise TransientHTTPError, "GET #{url} failed: #{response.code} #{response.message}" if response.code.match?(RETRYABLE_STATUS)

      raise "GET #{url} failed: #{response.code} #{response.message}"
    end
  end
end
