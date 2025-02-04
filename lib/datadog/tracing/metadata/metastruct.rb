# frozen_string_literal: true

module Datadog
  module Tracing
    module Metadata
      # Adds complex structures tagging behavior through metastruct
      module Metastruct
        def set_metastruct(metastruct)
          self.metastruct.merge!(metastruct)
        end

        def get_metastruct(key)
          metastruct[key]
        end

        def metastruct_size
          metastruct.size
        end

        protected

        def metastruct
          @metastruct ||= {}
        end
      end
    end
  end
end
