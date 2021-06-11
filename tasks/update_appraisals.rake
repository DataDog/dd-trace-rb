desc 'update gemfiles/ and .lock files based on Appraisals'
task :'update_appraisals' do
  sh "docker-compose run --rm tracer-2.1 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.2 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.3 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.4 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.5 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.6 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-2.7 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-3.0 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-jruby-9.2.0.0 /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
  sh "docker-compose run --rm tracer-jruby-9.2-latest /bin/bash -c 'rm -f Gemfile.lock && bundle install && bundle exec appraisal install'"
end
