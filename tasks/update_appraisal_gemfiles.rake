# frozen_string_literal: true

namespace :appraisal do
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
    ruby_version = {
      '2.1' => '2.1.10',
      '2.2' => '2.2.10',
      '2.3' => '2.3.8',
      '2.4' => '2.4.10',
      '2.5' => '2.5.9',
      '2.6' => '2.6.10',
      '2.7' => '2.7.6',
      '3.0' => '3.0.4',
      '3.1' => '3.1.2',
      '3.2' => '3.2.0',
      'jruby-9.2.8.0' => 'jruby-9.2.8.0',
      'jruby-9.2' => 'jruby-9.2.21.0',
      'jruby-9.3' => 'jruby-9.3.9.0',
      'jruby-9.4' => 'jruby-9.4.0.0',
    }[ruby_version]

    return "ruby_#{ruby_version}" if ruby_version =~ /^\d/

    ruby_version.tr('-', '_')
  end

  desc 'Generate Appraisal gemfiles. Takes a version list as argument, defaults to all'
  task :generate do |_task, args|
    ruby_versions(args.to_a).each do |ruby_version|
      cmd = []
      cmd << ['rm', '-vf', 'Gemfile.lock']
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << ['rm', '-vf', 'Gemfile.lock']

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
      cmd << ['rm', '-vf', 'Gemfile.lock']
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'install']
      cmd << ['rm', '-vf', 'Gemfile.lock']

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
      cmd << ['rm', '-vf', 'Gemfile.lock']
      cmd << ['gem', 'install', 'bundler', '-v', bundler_version(ruby_version)] if bundler_version(ruby_version)
      cmd << [*bundle(ruby_version), 'config', 'without', 'check']
      cmd << [*bundle(ruby_version), 'install']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'generate']
      cmd << [*bundle(ruby_version), 'exec', 'appraisal', 'update']
      cmd << ['rm', '-vf', 'Gemfile.lock']

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
      cmd << ['rm', '-vf', 'Gemfile.lock']
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
      cmd << ['rm', '-vf', 'Gemfile.lock']

      cmd = cmd.map { |c| c << '&&' }.flatten.tap(&:pop)

      p cmd
      p docker(ruby_version, cmd)
      sh docker(ruby_version, cmd).join(' ')
    end
  end
end

TRACER_VERSIONS = %w[
  2.1
  2.2
  2.3
  2.4
  2.5
  2.6
  2.7
  3.0
  3.1
  3.2
  jruby-9.2.8.0
  jruby-9.2
  jruby-9.3
  jruby-9.4
  #truffleruby-22.3.0
].freeze
# ADD NEW RUBIES HERE

FORCE_BUNDLER_VERSION = {
  # Some groups require bundler 1.x https://github.com/DataDog/dd-trace-rb/issues/2444
  '2.3' => '1.17.3',

  # 2.4.x seems to cause problems with appraisal
  '2.6' => '2.3.26',
  '2.7' => '2.3.26',
  '3.0' => '2.3.26',
  '3.1' => '2.3.26',
  '3.2' => '2.3.26',
}.freeze

desc 'Installs gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :install_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    forced_bundler_version = nil
    bundler_setup = 'gem update bundler'

    if FORCE_BUNDLER_VERSION.include?(version)
      forced_bundler_version = "_#{FORCE_BUNDLER_VERSION[version]}_"
      bundler_setup = "gem install bundler -v #{FORCE_BUNDLER_VERSION[version]}"
    end

    sh [
         "docker-compose run -e APPRAISAL_GROUP --no-deps --rm tracer-#{version} /bin/bash -c ",
         "'rm -f Gemfile.lock && #{bundler_setup} && bundle #{forced_bundler_version} install && ",
         # Appraisal runs `bundle check || bundle install` on `appraisal install`. This skips `bundle install` \
         # if the `Gemfile.lock` is satisfied by installed gems, even if there are `Gemfile` changes to be processed. \
         # Adding the `--without` option forces Appraisal to skip `bundle check` and always run `bundle install`. \
         # `--without` has a small side-effect of getting saving in the local bundler env, but we do not persist \
         # these changes outside of the current container. \
         "bundle exec appraisal #{forced_bundler_version} install --without force-appraisal-to-always-run-bundle-install'"
       ].join
  end
end

desc 'Update ALL gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :update_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    forced_bundler_version = nil
    bundler_setup = 'gem update bundler'

    if FORCE_BUNDLER_VERSION.include?(version)
      forced_bundler_version = "_#{FORCE_BUNDLER_VERSION[version]}_"
      bundler_setup = "gem install bundler -v #{FORCE_BUNDLER_VERSION[version]}"
    end

    sh "docker-compose run -e APPRAISAL_GROUP --no-deps --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && #{bundler_setup} && bundle #{forced_bundler_version} install && bundle exec appraisal #{forced_bundler_version} update'"
  end
end
