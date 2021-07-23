TRACER_VERSIONS = %w[
  2.1
  2.2
  2.3
  2.4
  2.5
  2.6
  2.7
  3.0
  jruby-9.2.0.0
  jruby-9.2-latest
].freeze

desc 'Installs gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :install_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    sh "docker-compose run --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  end
end

desc 'Update ALL gems based on Appraisals and Gemfile changes, ' \
     'accepts list of tracer versions as task argument, defaults to all versions.'
task :update_appraisal_gemfiles do |_task, args|
  tracer_version_arg = args.to_a
  versions = tracer_version_arg.empty? ? TRACER_VERSIONS : tracer_version_arg

  versions.each do |version|
    sh "docker-compose run --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && bundle install && bundle exec appraisal update'"
  end
end
