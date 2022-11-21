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
  jruby-9.2-latest
  jruby-9.3-latest
].freeze
# ADD NEW RUBIES HERE

desc 'Installs gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :install_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    sh "docker-compose run -e APPRAISAL_GROUP --no-deps --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && gem update bundler && bundle install && bundle exec appraisal install'"
  end
end

desc 'Update ALL gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :update_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    sh "docker-compose run -e APPRAISAL_GROUP --no-deps --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && gem update bundler && bundle install && bundle exec appraisal update'"
  end
end
