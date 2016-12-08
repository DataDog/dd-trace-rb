module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  class Monkey
    def self.patch_all
      require 'ddtrace/contrib/elasticsearch/core' if \
              defined?(Elasticsearch::Transport::VERSION) && \
              Gem::Version.new(Elasticsearch::Transport::VERSION) >= Gem::Version.new('1.0.0')

      require 'ddtrace/contrib/redis/core' if \
              defined?(Redis::VERSION) && \
              Gem::Version.new(Redis::VERSION) >= Gem::Version.new('3.0.0')
    end
  end
end
