require 'ddtrace/contrib/active_storage/events/delete'
require 'ddtrace/contrib/active_storage/events/delete_prefixed'
require 'ddtrace/contrib/active_storage/events/download'
require 'ddtrace/contrib/active_storage/events/download_chunk'
require 'ddtrace/contrib/active_storage/events/exist'
require 'ddtrace/contrib/active_storage/events/preview'
require 'ddtrace/contrib/active_storage/events/streaming_download'
require 'ddtrace/contrib/active_storage/events/transform'
require 'ddtrace/contrib/active_storage/events/update_metadata'
require 'ddtrace/contrib/active_storage/events/upload'
require 'ddtrace/contrib/active_storage/events/url'

module Datadog
  module Contrib
    module ActiveStorage
      # Defines collection of instrumented ActiveStorage events
      module Events
        ALL = [
          Events::Delete,
          Events::DeletePrefixed,
          Events::Download,
          Events::DownloadChunk,
          Events::Exist,
          Events::Preview,
          Events::StreamingDownload,
          Events::Transform,
          Events::UpdateMetadata,
          Events::Upload,
          Events::Url
        ].freeze

        module_function

        def all
          self::ALL
        end

        def subscriptions
          all.collect(&:subscriptions).collect(&:to_a).flatten
        end

        def subscribe!
          all.each(&:subscribe!)
        end
      end
    end
  end
end
