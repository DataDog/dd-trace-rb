# frozen_string_literal: true

require_relative '../../support'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module ActiveSupport
        module Cache
          # Support for Redis with ActiveSupport
          module Redis
            # Patching behavior for Redis with ActiveSupport
            module Patcher
              # For Rails < 5.2 w/ redis-activesupport...
              # When Redis is used, we can't only patch Cache::Store as it is
              # Cache::RedisStore, a sub-class of it that is used, in practice.
              # We need to do a per-method monkey patching as some of them might
              # be redefined, and some of them not. The latest version of redis-activesupport
              # redefines write but leaves untouched read and delete:
              # https://github.com/redis-store/redis-activesupport/blob/v4.1.5/lib/active_support/cache/redis_store.rb
              #
              # For Rails >= 5.2 w/o redis-activesupport...
              # ActiveSupport includes a Redis cache store internally, and does not require these overrides.
              # https://github.com/rails/rails/blob/master/activesupport/lib/active_support/cache/redis_cache_store.rb
              def patch_redis_store?(meth)
                ### BRAZE MODIFICATION
                # Braze does not use Redis with ActiveSupport::Cache (we use MemCacheStore
                # via Appboy::Cache). However, redis-activesupport is in the bundle as
                # unused baggage from the redis-rails meta-gem (we only need redis-actionpack
                # for dashboard session storage). Its presence defines
                # ActiveSupport::Cache::RedisStore, which causes the check below to return
                # true and instrumentation to target RedisStore instead of Store — silently
                # breaking MemCacheStore tracing.
                #
                # Note: upstream fixed this independently in v2.2.0 (PR #3772) by changing
                # cache_store_class to return [RedisStore, Store] instead of just RedisStore,
                # so Store is always prepended. This override is now belt-and-suspenders but
                # we keep it because:
                #   1. It's low risk (5 lines) and proven stable across rebase cycles
                #   2. Changing redis-rails → redis-actionpack in platform has nontrivial QA
                #   3. dd-trace-rb 3.0 will delete this entire legacy patching code path
                #      (DEV-3.0 annotations in cache/patcher.rb and cache/instrumentation.rb)
                #
                # See: docs/plans/2026-02-13-v2.27.0-rebase-qa-plan.md (Phase 1C)
                return false
                ### END BRAZE MODIFICATION
                # rubocop:disable Lint/UnreachableCode
                !Gem.loaded_specs['redis-activesupport'].nil? \
                  && defined?(::ActiveSupport::Cache::RedisStore) \
                  && ::ActiveSupport::Cache::RedisStore.instance_methods(false).include?(meth)
                # rubocop:enable Lint/UnreachableCode
              end

              # Patches the Rails built-in Redis cache backend `redis_cache_store`, added in Rails 5.2.
              # We avoid loading the RedisCacheStore class, as it invokes the statement `gem "redis", ">= 4.0.1"` which
              # fails if the application is using an old version of Redis, or not using Redis at all.
              # @see https://github.com/rails/rails/blob/d0dcb8fa6073a0c4d42600c15e82e3bb386b27d3/activesupport/lib/active_support/cache/redis_cache_store.rb#L4
              def patch_redis_cache_store?(meth)
                Gem.loaded_specs['redis'] &&
                  Support.fully_loaded?(::ActiveSupport::Cache, :RedisCacheStore) &&
                  ::ActiveSupport::Cache::RedisCacheStore.instance_methods(false).include?(meth)
              end

              def cache_store_class(meth)
                if patch_redis_store?(meth)
                  [::ActiveSupport::Cache::RedisStore, ::ActiveSupport::Cache::Store]
                elsif patch_redis_cache_store?(meth)
                  [::ActiveSupport::Cache::RedisCacheStore, ::ActiveSupport::Cache::Store]
                else
                  super
                end
              end
            end

            # Decorate Cache patcher with Redis support
            Cache::Patcher.singleton_class.prepend(Redis::Patcher)
          end
        end
      end
    end
  end
end
