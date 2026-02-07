# frozen_string_literal: true

require_relative 'events/delete'
require_relative 'events/delete_prefixed'
require_relative 'events/download'
require_relative 'events/download_chunk'
require_relative 'events/exist'
require_relative 'events/preview'
require_relative 'events/streaming_download'
require_relative 'events/transform'
require_relative 'events/update_metadata'
require_relative 'events/upload'
require_relative 'events/url'

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
