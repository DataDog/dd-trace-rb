module Datadog
  # TODO[manu]: write docs
  module RendererExtension
    def render_template(*args)
      ActiveSupport::Notifications.instrument('start_render_template.action_view')
      super(*args)
    end
  end

  # TODO[manu]: write docs
  module PartialRendererExtension
    def render_partial(*args)
      ActiveSupport::Notifications.instrument('start_render_partial.action_view')
      super(*args)
    end
  end

  # CacheStoreReadExtension contains a new read function that notifies
  # the framework of a read, then calls read.
  module CacheStoreReadExtension
    def read(*args)
      ActiveSupport::Notifications.instrument('start_cache_read.active_support')
      super(*args)
    end
  end

  # CacheStoreFetchExtension contains a new fetch function that notifies
  # the framework of a fetch, then calls fetch.
  module CacheStoreFetchExtension
    # It might seem redundant to instrument both read and fetch since
    # fetch very often calls read. But there's no garantee of this, in
    # some cases fetch can call directly read_entry without calling read.
    def fetch(*args)
      ActiveSupport::Notifications.instrument('start_cache_fetch.active_support')
      super(*args)
    end
  end

  # CacheWriteReadExtension contains a new read function that notifies
  # the framework of a write, then calls write.
  module CacheStoreWriteExtension
    def write(*args)
      ActiveSupport::Notifications.instrument('start_cache_write.active_support')
      super(*args)
    end
  end

  # CacheDeleteExtension contains a new read function that notifies
  # the framework of a delete, then calls delete.
  module CacheStoreDeleteExtension
    def delete(*args)
      ActiveSupport::Notifications.instrument('start_cache_delete.active_support')
      super(*args)
    end
  end

  # RailsPatcher contains function to patch the Rails libraries.
  module RailsPatcher
    module_function

    def patch_renderer
      ::ActionView::Renderer.prepend Datadog::RendererExtension
      ::ActionView::PartialRenderer.prepend Datadog::PartialRendererExtension
    end

    def patch_cache_store
      # When Redis is used, we can't only patch Cache::Store as it is
      # Cache::RedisStore, a sub-class of it that is used, in practice.
      # We need to do a per-method monkey patching as some of them might
      # be redefined, and some of them not. The latest version of redis-activesupport
      # redefines write but leaves untouched read and delete:
      # https://github.com/redis-store/redis-activesupport/blob/master/lib/active_support/cache/redis_store.rb

      { read: Datadog::CacheStoreReadExtension,
        fetch: Datadog::CacheStoreFetchExtension,
        write: Datadog::CacheStoreWriteExtension,
        delete: Datadog::CacheStoreDeleteExtension }.each do |k, v|
        c = if defined?(::ActiveSupport::Cache::RedisStore) &&
               ::ActiveSupport::Cache::RedisStore.instance_methods(false).include?(k)
              ::ActiveSupport::Cache::RedisStore
            else
              ::ActiveSupport::Cache::Store
            end
        Datadog::Tracer.log.debug("monkey patching #{c}.#{k} with #{v}.#{k}")
        c.prepend v
      end
    end
  end
end
