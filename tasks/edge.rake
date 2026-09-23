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
      "ai_guard:ruby_llm" => "ruby_llm",
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
      "shoryuken" => ["shoryuken", "aws-sdk-sqs"],
      "sneakers" => "kicks",
      "stripe" => "stripe",
      "waterdrop" => "waterdrop",
      # Add more integrations here, when their gems need to track the latest
      # release; the gems may live in a shared group, as long as each entry
      # lists only the gems that integration owns
    }

    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gems|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        RuntimeMatcher.match?(rubies)
      end

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        # A group's gems aren't all present in every ruby-version gemfile (e.g. faraday-follow_redirects
        # is latest-only); `bundle lock --update` errors out if asked to update a gem that isn't there.
        lockfile_specs = Bundler::LockfileParser.new(Bundler.read_file("#{gemfile}.lock")).specs.map(&:name)
        gems_to_update = Array(gems).select { |gem| lockfile_specs.include?(gem) }

        next if gems_to_update.empty?

        update_flags = gems_to_update.map { |gem| "--update=#{gem}" }.join(" ")

        Bundler.with_unbundled_env do
          output, status = Open3.capture2e({"BUNDLE_GEMFILE" => gemfile.to_s}, "bundle lock #{update_flags}")

          puts output
          raise "bundle lock failed for #{gemfile}" unless status.success?
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
