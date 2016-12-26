module Datadog
  module Contrib
    module Elasticsearch
      # Quantize contains ES-specific resource quantization tools.
      module Quantize
        ID_REGEXP = %r{\/([0-9]+)([\/\?]|$)}
        ID_PLACEHOLDER = '/?\2'.freeze

        INDEX_REGEXP = /[0-9]{2,}/
        INDEX_PLACEHOLDER = '?'.freeze

        module_function

        # Very basic quantization, complex processing should be done in the agent
        def format_url(url)
          quantized_url = url.gsub(ID_REGEXP, ID_PLACEHOLDER)
          quantized_url.gsub(INDEX_REGEXP, INDEX_PLACEHOLDER)
        end
      end
    end
  end
end
