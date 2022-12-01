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
].freeze
# ADD NEW RUBIES HERE

FORCE_BUNDLER_VERSION = {
  '2.3' => '1.17.3', # Some groups require bundler 1.x https://github.com/DataDog/dd-trace-rb/issues/2444
  'jruby-9.2.8.0' => '2.3.6', # 2.3.26 seems to be broken https://github.com/DataDog/dd-trace-rb/issues/2443
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
