require "open3"
require "set"

require_relative "appraisal_conversion"
require_relative "runtime_matcher"

# rubocop:disable Metrics/BlockLength
namespace :edge do
  desc "Update all the groups with gemspec dependencies"
  task :gemspec do
    candidates = Set.new

    TEST_METADATA.each do |_, metadata|
      metadata.each do |group, rubies|
        candidates << group if RuntimeMatcher.match?(rubies)
      end
    end

    gemspec_runtime_dependencies = Gem::Specification.load("datadog.gemspec").dependencies

    candidates.each do |group|
      next if group.empty?

      gemfile = AppraisalConversion.to_bundle_gemfile(group)

      Bundler.with_unbundled_env do
        output, = Open3.capture2e(
          {"BUNDLE_GEMFILE" => gemfile.to_s},
          "bundle lock --update #{gemspec_runtime_dependencies.map(&:name).join(" ")}"
        )

        puts output
      end
    end
  end

  desc "Update groups with targeted dependencies"
  task :update do |_t, args|
    # Naming convention:
    #
    # Key: integration name, the same as the name of spec task in Rakefile and MatrixFile
    # Value: gem name, or a list of gem names when the group bundles several that
    # the integration owns (e.g. ethon + typhoeus, or the aws-sdk family)
    allowlist = {
      "stripe" => "stripe",
      "elasticsearch" => "elasticsearch",
      "opensearch" => "opensearch-ruby",
      "rack" => "rack",
      "faraday" => "faraday",
      "excon" => "excon",
      "rest_client" => "rest-client",
      "mongodb" => "mongo",
      "dalli" => "dalli",
      "redis" => "redis",
      "karafka" => "karafka",
      "httprb" => "http",
      "httpclient" => "httpclient",
      "ethon" => ["ethon", "typhoeus"],
      "aws" => ["aws-sdk", "aws-sdk-core"],
      "shoryuken" => ["shoryuken", "aws-sdk-sqs"],
      # Add more integrations here, when their gems need to track the latest
      # release; the gems may live in a shared group, as long as each entry
      # lists only the gems that integration owns
    }

    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gems|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        RuntimeMatcher.match?(rubies)
      end

      update_flags = Array(gems).map { |gem| "--update=#{gem}" }.join(" ")

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          output, = Open3.capture2e({"BUNDLE_GEMFILE" => gemfile.to_s}, "bundle lock #{update_flags}")

          puts output
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
