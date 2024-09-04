# frozen_string_literal: true

require 'open3'
require 'pathname'

namespace :edge do
  desc 'Update edge build for current ruby runtime'
  task :update do
    ruby_version = RUBY_VERSION[0..2]

    prefix = "#{RUBY_ENGINE}-#{ruby_version}"
    project_root = Pathname.new("#{__dir__}/../").cleanpath.to_s

    [
      'stripe',
      'elasticsearch',
      # more integrations here
    ].each do |integration|
      candidates = TEST_METADATA.fetch(integration).select do |_, rubies|
        if RUBY_PLATFORM == 'java'
          rubies.include?("✅ #{ruby_version}") && rubies.include?('✅ jruby')
        else
          rubies.include?("✅ #{ruby_version}")
        end
      end

      gemfiles = candidates.keys.map do |group|
        "#{project_root}/gemfiles/#{prefix}-#{group}.gemfile".tr('-', '_')
      end

      gemfiles.each do |gemfile|
        Bundler.with_unbundled_env do
          output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile }, "bundle lock --update=#{integration}")

          puts output
        end
      end
    end
  end
end
