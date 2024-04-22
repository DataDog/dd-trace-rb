# frozen_string_literal: true

require 'pry'

namespace :appraisal do # rubocop:disable Metrics/BlockLength
  def ruby_versions(versions)
    return TRACER_VERSIONS if versions.empty?

    TRACER_VERSIONS & versions
  end

  def bundler_version(ruby_version)
    FORCE_BUNDLER_VERSION[ruby_version]
  end

  def force_bundler_version(ruby_version)
    force_gem_version(bundler_version(ruby_version))
  end

  def force_gem_version(version)
    # format first bin script arg to force a gem version
    #
    # see https://github.com/rubygems/rubygems/blob/7a144f3374f6a400cc9832f072dc1fc0bca8c724/lib/rubygems/installer.rb#L764-L771

    return if version.nil?

    "_#{version}_"
  end

  def bundle(ruby_version)
    ['bundle', force_bundler_version(ruby_version)].compact
  end

  def docker(ruby_version, cmd)
    [
      'docker-compose', 'run',
      '--no-deps',                                   # don't start services
      '-e', 'APPRAISAL_GROUP',                       # pass appraisal group if defined
      '-e', 'APPRAISAL_SKIP_BUNDLE_CHECK',           # pass appraisal check skip if defined
      '--rm',                                        # clean up container
      "tracer-#{ruby_version}",                      # use specific ruby engine and version
      '/bin/bash', '-c', "'#{cmd.join(' ')}'"        # call command in bash
    ]
  end

  def lockfile_prefix(ruby_version)
    return "ruby_#{ruby_version}" if ruby_version =~ /^\d/

    ruby_version.tr('-', '_')
  end

  desc 'Generate Appraisal gemfiles. Takes a version list as argument, defaults to all'
  task :generate do |_task, args|
    ruby_versions(args.to_a).each do |ruby_version|
      cmd = []
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end
  end

  desc 'Generate Appraisal gemfile.lock. Takes a version list as argument, defaults to all'
  task :lock do |_task, args|
    ruby_versions(args.to_a).each do |ruby_version|
      cmd = []
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'bundle lock']

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end
  end

  desc 'Install Appraisal gemfiles. Takes a version list as argument, defaults to all'
  task :install do |_task, args|
    ENV['APPRAISAL_SKIP_BUNDLE_CHECK'] = 'y'

    ruby_versions(args.to_a).each do |ruby_version|
      cmd = []
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'install']

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end

    ENV.delete('APPRAISAL_SKIP_BUNDLE_CHECK')
  end

  desc 'Update Appraisal gemfiles. Takes a version list as argument, defaults to all'
  task :update do |_task, args|
    ruby_versions(args.to_a).each do |ruby_version|
      cmd = []
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'update']

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end
  end

  desc 'Add all platforms to Appraisal gemfiles. Takes a version list as argument, defaults to all'
  task :platform do |_task, args|
    ruby_versions(args.to_a).each do |ruby_version|
      next if ruby_version.start_with?('jruby-')

      cmd = []
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      p lockfile_prefix(ruby_version)
      Dir["gemfiles/#{lockfile_prefix(ruby_version)}_*.gemfile.lock"].each do |lockfile|
        gemfile = lockfile.gsub(/\.lock$/, '')
        cmd << ['env', "BUNDLE_GEMFILE=#{gemfile}",
                *bundle(ruby_version), 'lock',
                '--lockfile', lockfile,
                '--add-platform', 'x86_64-linux']
        cmd << ['env', "BUNDLE_GEMFILE=#{gemfile}",
                *bundle(ruby_version), 'lock',
                '--lockfile', lockfile,
                '--add-platform', 'aarch64-linux']
      end

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end
  end

  desc 'Remove obsolete appraisal files that are not used by the test matrix'
  task :clean do
    appraisal_files = Dir.glob('gemfiles/*')

    ruby_versions = ['2.5', '2.6', '2.7', '3.0', '3.1', '3.2', '3.3']
    # JRuby skips 2.7 and 3.0
    jruby_cruby_mapping = {
      '9.4' => '3.1',
      '9.3' => '2.6',
      '9.2' => '2.5'
    }

    TEST_METADATA.each do |_, spec_metadata|
      spec_metadata.each do |group, versions|
        ruby_versions.each do |ruby_version|
          next unless versions.include?("✅ #{ruby_version}")

          appraisal_files -= [
            "gemfiles/ruby_#{ruby_version}_#{group.tr('-', '_')}.gemfile",
            "gemfiles/ruby_#{ruby_version}_#{group.tr('-', '_')}.gemfile.lock"
          ]
        end

        next unless versions.include?('✅ jruby')

        jruby_cruby_mapping.each do |jruby_version, ruby_version|
          next unless versions.include?("✅ #{ruby_version}")

          appraisal_files -= [
            "gemfiles/jruby_#{jruby_version}_#{group.tr('-', '_')}.gemfile",
            "gemfiles/jruby_#{jruby_version}_#{group.tr('-', '_')}.gemfile.lock"
          ]
        end
      end
    end

    FileUtils.rm(appraisal_files)
  end
end

TRACER_VERSIONS = [
  '2.5',
  '2.6',
  '2.7',
  '3.0',
  '3.1',
  '3.2',
  '3.3',
  # ADD NEW RUBIES HERE
  'jruby-9.2',
  'jruby-9.3',
  'jruby-9.4',
].freeze

FORCE_BUNDLER_VERSION = {
  # Some groups require bundler 1.x https://github.com/DataDog/dd-trace-rb/issues/2444
  '2.3' => '1.17.3',

  # 2.4.x seems to cause problems with appraisal
  '2.6' => '2.3.26',
  '2.7' => '2.3.26',
  '3.0' => '2.3.26',
  '3.1' => '2.3.26',
  '3.2' => '2.3.26',
  '3.3' => '2.3.26',
}.freeze
