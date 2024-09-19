require 'open3'

require_relative 'appraisal_conversion'

# rubocop:disable Metrics/BlockLength
namespace :edge do
  desc 'Update all the groups from the matrix'
  task :update do |_t, args|
    ruby_version = RUBY_VERSION[0..2]
    allowlist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      # Add more integrations here, when they are extracted to its own isolated group
    }

    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gem|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      candidates.each do |group, _|
        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          puts "======== Updating #{integration} in #{gemfile} ========\n"
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end

  desc 'Update the `latest` group from the matrix'
  task :latest do |_t, args|
    ruby_version = RUBY_VERSION[0..2]
    allowlist = {
      'stripe' => 'stripe',
      'elasticsearch' => 'elasticsearch',
      'opensearch' => 'opensearch-ruby',
      # Add more integrations here, when hey are extracted to its own isolated group
    }

    allowlist = allowlist.slice(*args.extras) if args.extras.any?

    allowlist.each do |integration, gem|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      candidates.each do |group, _|
        # ONLY pick the latest group
        next unless group.end_with?('-latest')

        gemfile = AppraisalConversion.to_bundle_gemfile(group)

        Bundler.with_unbundled_env do
          puts "======== Updating #{integration} in #{gemfile} ========\n"
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle lock --update=#{gem}")

          puts output
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
