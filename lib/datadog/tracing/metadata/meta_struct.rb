# frozen_string_literal: true

module Datadog
  module Tracing
    module Metadata
      # Adds complex structures tagging behavior through meta_struct
      # @public_api
      module MetaStruct
        def set_meta_struct(meta_struct)
          self.meta_struct.merge!(meta_struct)
        end

        protected

        def meta_struct
          @meta_struct ||= {}
        end
      end
    end
  end
end
