# frozen_string_literal: true

module Datadog
  module Tracing
    module Metadata
      # Adds complex structures tagging behavior through metastruct
      module Metastruct
        def metastruct=(second)
          @metastruct = second
        end

        def deep_merge_metastruct!(second)
          merger = proc do |_, v1, v2|
            if v1.is_a?(Hash) && v2.is_a?(Hash)
              v1.merge(v2, &merger)
            elsif v1.is_a?(Array) && v2.is_a?(Array)
              v1.concat(v2)
            elsif v2.nil?
              v1
            else
              v2
            end
          end
          metastruct.merge!(second.to_h, &merger)
        end

        def get_metastruct(key)
          metastruct[key]
        end

        protected

        def metastruct
          @metastruct ||= {}
        end
      end
    end
  end
end
