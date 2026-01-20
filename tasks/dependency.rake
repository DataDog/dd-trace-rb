require_relative 'appraisal_conversion'

namespace :dependency do
  # Replacement for `bundle exec appraisal list`
  desc "List dependencies for #{AppraisalConversion.runtime_identifier}"
  task :list do |t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern, base: AppraisalConversion.root_path)

    puts "Ahoy! Here is a list of gemfiles you are looking for:\n\n"

    puts "========================================\n"
    puts gemfiles
    puts "========================================\n"

    puts "You can do a bunch of cool stuff by assigning a gemfile path to the BUNDLE_GEMFILE environment variable, like:\n"
    puts "`BUNDLE_GEMFILE=#{gemfiles.sample} bundle install`\n\n"
  end

  # Replacement for `bundle exec appraisal generate`
  desc "Generate dependencies for #{AppraisalConversion.runtime_identifier}"
  task :generate do |t, args|
    sh 'bundle exec ruby appraisal/generate.rb'
  end

  task :exec do |t, args|
    command = args.extras.any? ? args.extras.first : 'bundle version'

    gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern, base: AppraisalConversion.root_path)

    gemfiles.each do |gemfile|
      Bundler.with_unbundled_env do
        sh({'BUNDLE_GEMFILE' => gemfile.to_s}, command)
      end
    end
  end

  # Replacement for `bundle exec appraisal install`
  # Generates lockfiles and runs dependencies gemspecs.
  # `bundle install` is used instead of `bundle lock` because
  # it checks each gem's gemspec requirements (e.g. required_ruby_version, required_rubygems_version).
  desc "Install dependencies for #{AppraisalConversion.runtime_identifier}"
  task :install do |t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern)

    gemfiles.each do |gemfile|
      Bundler.with_unbundled_env do
        sh({'BUNDLE_GEMFILE' => gemfile.to_s}, 'bundle install')
      end
    end
  end
end
