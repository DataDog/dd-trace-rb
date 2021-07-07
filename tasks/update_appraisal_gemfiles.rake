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

desc 'update gemfiles/*.gemfile and gemfiles/*.lock files based on Appraisals'
task :update_appraisal_gemfiles do
  TRACER_VERSIONS.each do |version|
    cmd = "docker-compose run --rm tracer-#{version} /bin/bash -c " \
      "'rm -f Gemfile.lock && bundle install && bundle exec appraisal update'"

    puts cmd
    sh cmd
  end
end
