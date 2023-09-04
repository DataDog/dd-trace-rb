require 'bundler/gem_tasks'
require 'ddtrace/version'
require 'rubocop/rake_task' if Gem.loaded_specs.key? 'rubocop'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'yard'
require 'os'

Dir.glob('tasks/*.rake').each { |r| import r }

TEST_METADATA = {
  'spec:main' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => nil
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'core-old'
    }
  ],
  'spec:appsec:main' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => nil
    }
  ],
  'spec:contrib' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => nil
    }
  ],
  'spec:opentracer' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => nil
    }
  ],
  'spec:opentelemetry' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ❌ jruby',
      :appraisal_group => 'opentelemetry'
    }
  ],
  'spec:action_pack' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    }
  ],
  'spec:action_view' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    }
  ],
  'spec:active_model_serializers' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:active_record' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'activerecord-3'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'activerecord-4'
    }
  ],
  'spec:active_support' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '✅ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    }
  ],
  'spec:autoinstrument' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:aws' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:concurrent_ruby' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:dalli' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:delayed_job' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:elasticsearch' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:ethon' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:excon' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:faraday' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:grape' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:graphql' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:grpc' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ❌ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:http' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:httpclient' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:httprb' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:kafka' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:lograge' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:minitest' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:mongodb' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:mysql2' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ❌ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:opensearch' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:pg' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ❌ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:presto' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:que' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:racecar' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:rack' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:rake' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:resque' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'resque2-redis3'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'resque2-redis4'
    }
  ],
  'spec:rest_client' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:roda' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:rspec' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:semantic_logger' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:sequel' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:shoryuken' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:sidekiq' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:sneakers' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:stripe' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:sucker_punch' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:suite' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:qless' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib-old'
    }
  ],
  'spec:rails' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-mysql2'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-mysql2'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-postgres'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-postgres'
    }
  ],
  'spec:railsautoinstrument' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-postgres'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres'
    }
  ],
  'spec:railsdisableenv' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-postgres'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-postgres'
    }
  ],
  'spec:railsredis_activesupport' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails32-postgres-redis'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-postgres-redis'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres-redis-activesupport'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres-redis-activesupport'
    }
  ],
  'spec:railsactivejob' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-postgres-sidekiq'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres-sidekiq'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres-sidekiq'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-postgres-sidekiq'
    }
  ],
  'spec:railssemanticlogger' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails4-semantic-logger'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-semantic-logger'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-semantic-logger'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-semantic-logger'
    }
  ],
  'spec:action_cable' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-mysql2'
    }
  ],
  'spec:action_mailer' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-mysql2'
    }
  ],
  'spec:railsredis' => [
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails5-postgres-redis'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ✅ jruby',
      :appraisal_group => 'rails6-postgres-redis'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'rails61-postgres-redis'
    }
  ],
  'spec:hanami' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'hanami-1'
    }
  ],
  'spec:sinatra' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'sinatra'
    }
  ],
  'spec:redis' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'redis-3'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'redis-4'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'redis-5'
    }
  ],
  'spec:cucumber' => [
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber3'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber4'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber5'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber6'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber7'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'cucumber8'
    }
  ],
  'spec:appsec:rack' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:appsec:sinatra' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:appsec:devise' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      :appraisal_group => 'contrib'
    }
  ],
  'spec:appsec:rails' => [
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'rails32-mysql2'
    },
    {
      :matrix => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ❌ 2.4 / ❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'rails4-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'rails5-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ❌ 3.3 / ❌ jruby',
      :appraisal_group => 'rails6-mysql2'
    },
    {
      :matrix => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ❌ jruby',
      :appraisal_group => 'rails61-mysql2'
    }
  ]
}.freeze

task :test, [:rake_task] do |_, args|
  spec_task = args.rake_task
  spec_metadata = TEST_METADATA[spec_task]

  next unless spec_metadata

  total_executors = ENV.key?('CIRCLE_NODE_TOTAL') ? ENV['CIRCLE_NODE_TOTAL'].to_i : nil
  current_executor = ENV.key?('CIRCLE_NODE_INDEX') ? ENV['CIRCLE_NODE_INDEX'].to_i : nil

  spec_metadata.each do |specs|
    next if RUBY_PLATFORM == 'java' && !specs[:matrix].include?('jruby')

    ruby_version = RUBY_VERSION[0..2]

    next unless specs[:matrix].include?("✅ #{ruby_version}")

    ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
                     "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
                   else
                     "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
                   end

    command = if specs[:appraisal_group]
                "bundle exec appraisal #{ruby_runtime}-#{specs[:appraisal_group]} rake #{spec_task}"
              else
                "bundle exec rake #{spec_task}"
              end

    if total_executors && current_executor && total_executors > 1
      @execution_count ||= 0
      @execution_count += 1
      sh(command) if @execution_count % total_executors == current_executor
    else
      sh(command)
    end
  end
end

desc 'Run RSpec'
# rubocop:disable Metrics/BlockLength
namespace :spec do
  task all: [:main, :benchmark,
             :rails, :railsredis, :railsredis_activesupport, :railsactivejob,
             :elasticsearch, :http, :redis, :sidekiq, :sinatra, :hanami, :hanami_autoinstrument]

  RSpec::Core::RakeTask.new(:main) do |t, args|
    t.pattern = 'spec/**/*_spec.rb'
    t.exclude_pattern = 'spec/**/{contrib,benchmark,redis,opentracer,auto_instrument,opentelemetry}/**/*_spec.rb,'\
                        ' spec/**/{auto_instrument,opentelemetry}_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end
  if RUBY_ENGINE == 'ruby' && OS.linux? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.3.0') \
    && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.3.0')
    # "bundle exec rake compile" currently only works on MRI Ruby on Linux
    Rake::Task[:main].enhance([:clean])
    Rake::Task[:main].enhance([:compile])
  end

  RSpec::Core::RakeTask.new(:benchmark) do |t, args|
    t.pattern = 'spec/ddtrace/benchmark/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:opentracer) do |t, args|
    t.pattern = 'spec/datadog/opentracer/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:opentelemetry) do |t, args|
    t.pattern = 'spec/datadog/opentelemetry/**/*_spec.rb,spec/datadog/opentelemetry_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:rails) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*_spec.rb'
    t.exclude_pattern = 'spec/datadog/tracing/contrib/rails/**/*{active_job,disable_env,redis_cache,auto_instrument,'\
                        'semantic_logger}*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsredis) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsredis_activesupport) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*redis*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    # Flag used to tell specs the expected configuration (so that they break if they're not being setup correctly)
    ENV['EXPECT_RAILS_ACTIVESUPPORT'] = 'true'
  end

  RSpec::Core::RakeTask.new(:railsactivejob) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*active_job*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsdisableenv) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*disable_env*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:railsautoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*auto_instrument*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:hanami) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:hanami_autoinstrument) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/hanami/**/*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')

    ENV['TEST_AUTO_INSTRUMENT'] = 'true'
  end

  RSpec::Core::RakeTask.new(:autoinstrument) do |t, args|
    t.pattern = 'spec/ddtrace/auto_instrument_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:yjit) do |t, args|
    t.pattern = 'spec/datadog/core/runtime/metrics_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  # rails_semantic_logger is the dog at the dog park that doesnt play nicely with other
  # logging gems, aka it tries to bite/monkeypatch them, so we have to put it in its own appraisal and rake task
  # in order to isolate its effects for rails logs auto injection
  RSpec::Core::RakeTask.new(:railssemanticlogger) do |t, args|
    t.pattern = 'spec/datadog/tracing/contrib/rails/**/*rails_semantic_logger*_spec.rb'
    t.rspec_opts = args.to_a.join(' ')
  end

  RSpec::Core::RakeTask.new(:contrib) do |t, args|
    contrib_paths = [
      'analytics',
      'configurable',
      'configuration/*',
      'configuration/resolvers/*',
      'extensions',
      'integration',
      'patchable',
      'patcher',
      'registerable',
      'registry',
      'registry/*',
      'propagation/**/*'
    ].join(',')

    t.pattern = "spec/**/contrib/{#{contrib_paths}}_spec.rb"
    t.rspec_opts = args.to_a.join(' ')
  end

  # Datadog Tracing integrations
  [
    :action_cable,
    :action_mailer,
    :action_pack,
    :action_view,
    :active_model_serializers,
    :active_record,
    :active_support,
    :aws,
    :concurrent_ruby,
    :dalli,
    :delayed_job,
    :elasticsearch,
    :ethon,
    :excon,
    :faraday,
    :grape,
    :graphql,
    :grpc,
    :http,
    :httpclient,
    :httprb,
    :kafka,
    :lograge,
    :mongodb,
    :mysql2,
    :opensearch,
    :pg,
    :presto,
    :qless,
    :que,
    :racecar,
    :rack,
    :rake,
    :redis,
    :resque,
    :roda,
    :rest_client,
    :semantic_logger,
    :sequel,
    :shoryuken,
    :sidekiq,
    :sinatra,
    :sneakers,
    :stripe,
    :sucker_punch,
    :suite
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/tracing/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  # Datadog CI integrations
  [
    :cucumber,
    :rspec,
    :minitest
  ].each do |contrib|
    RSpec::Core::RakeTask.new(contrib) do |t, args|
      t.pattern = "spec/datadog/ci/contrib/#{contrib}/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end

  namespace :appsec do
    task all: [:main, :rack, :rails, :sinatra, :devise]

    # Datadog AppSec main specs
    RSpec::Core::RakeTask.new(:main) do |t, args|
      t.pattern = 'spec/datadog/appsec/**/*_spec.rb'
      t.exclude_pattern = 'spec/datadog/appsec/**/{contrib,auto_instrument}/**/*_spec.rb,'\
                          ' spec/datadog/appsec/**/{auto_instrument,autoload}_spec.rb'
      t.rspec_opts = args.to_a.join(' ')
    end

    # Datadog AppSec integrations
    [
      :rack,
      :sinatra,
      :rails,
      :devise,
    ].each do |contrib|
      RSpec::Core::RakeTask.new(contrib) do |t, args|
        t.pattern = "spec/datadog/appsec/contrib/#{contrib}/**/*_spec.rb"
        t.rspec_opts = args.to_a.join(' ')
      end
    end
  end

  task appsec: [:'appsec:all']
end

if defined?(RuboCop::RakeTask)
  RuboCop::RakeTask.new(:rubocop) do |_t|
  end
end

YARD::Rake::YardocTask.new(:docs) do |t|
  # Options defined in `.yardopts` are read first, then merged with
  # options defined here.
  #
  # It's recommended to define options in `.yardopts` instead of here,
  # as `.yardopts` can be read by external YARD tools, like the
  # hot-reload YARD server `yard server --reload`.

  t.options += ['--title', "ddtrace #{DDTrace::VERSION::STRING} documentation"]
end

# Jobs are parallelized if running in CI.

desc 'CI task; it runs all tests for current version of Ruby'
task :ci do
  TEST_METADATA.each_key do |spec_task|
    Rake::Task['test'].execute(Rake::TaskArguments.new([:rake_task], [spec_task]))
  end
end

namespace :coverage do
  # Generates one global report for all tracer tests
  task :report do
    require 'simplecov'

    resultset_files = Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/.resultset.json"] +
      Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/**/.resultset.json"]

    SimpleCov.collate resultset_files do
      coverage_dir "#{ENV.fetch('COVERAGE_DIR', 'coverage')}/report"
      if ENV['CI'] == 'true'
        require 'simplecov-cobertura'
        formatter SimpleCov::Formatter::MultiFormatter.new(
          [SimpleCov::Formatter::HTMLFormatter,
           SimpleCov::Formatter::CoberturaFormatter] # Used by codecov
        )
      else
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end

  # Generates one report for each Ruby version
  task :report_per_ruby_version do
    require 'simplecov'

    versions = Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/*"].map { |f| File.basename(f) }
    versions.map do |version|
      puts "Generating report for: #{version}"
      SimpleCov.collate Dir["#{ENV.fetch('COVERAGE_DIR', 'coverage')}/versions/#{version}/**/.resultset.json"] do
        coverage_dir "#{ENV.fetch('COVERAGE_DIR', 'coverage')}/report/versions/#{version}"
        formatter SimpleCov::Formatter::HTMLFormatter
      end
    end
  end
end

namespace :changelog do
  task :format do
    require 'pimpmychangelog'

    PimpMyChangelog::CLI.run!
  end
end

Rake::ExtensionTask.new("ddtrace_profiling_native_extension.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
  ext.ext_dir = 'ext/ddtrace_profiling_native_extension'
end

Rake::ExtensionTask.new("ddtrace_profiling_loader.#{RUBY_VERSION}_#{RUBY_PLATFORM}") do |ext|
  ext.ext_dir = 'ext/ddtrace_profiling_loader'
end

desc 'Runs rubocop + main test suite'
task default: ['rubocop', 'typecheck', 'spec:main']

desc 'Runs the default task in parallel'
multitask fastdefault: ['rubocop', 'typecheck', 'spec:main']
