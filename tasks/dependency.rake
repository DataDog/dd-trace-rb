require 'open3'

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

  # Replacement for `bundle exec appraisal bundle lock`
  desc "Lock dependencies for #{AppraisalConversion.runtime_identifier}"
  task :lock do |t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern)

    gemfiles.each do |gemfile|
      Bundler.with_unbundled_env do
        command = +'bundle lock'
        command << ' --add-platform x86_64-linux aarch64-linux' unless RUBY_PLATFORM == 'java'
        output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, command)

        puts output
      end
    end
  end

  # Replacement for `bundle exec appraisal install`
  desc "Install dependencies for #{AppraisalConversion.runtime_identifier}"
  task :install => :lock do |t, args|
    pattern = args.extras.any? ? args.extras : AppraisalConversion.gemfile_pattern

    gemfiles = Dir.glob(pattern)

    gemfiles.each do |gemfile|
      Bundler.with_unbundled_env do
        output, = Open3.capture2e({ 'BUNDLE_GEMFILE' => gemfile.to_s }, "bundle check || bundle install")

        puts output
      end
    end
  end
end
