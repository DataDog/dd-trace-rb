# typed: false

require 'datadog/tracing/contrib/active_storage/events/delete'
require 'datadog/tracing/contrib/active_storage/events/delete_prefixed'
require 'datadog/tracing/contrib/active_storage/events/download'
require 'datadog/tracing/contrib/active_storage/events/download_chunk'
require 'datadog/tracing/contrib/active_storage/events/exist'
require 'datadog/tracing/contrib/active_storage/events/preview'
require 'datadog/tracing/contrib/active_storage/events/streaming_download'
require 'datadog/tracing/contrib/active_storage/events/transform'
require 'datadog/tracing/contrib/active_storage/events/update_metadata'
require 'datadog/tracing/contrib/active_storage/events/upload'
require 'datadog/tracing/contrib/active_storage/events/url'

module Datadog
  module Tracing
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
end
