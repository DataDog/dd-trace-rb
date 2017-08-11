module Datadog
  module Contrib
    # MongoDB module includes classes and functions to instrument MongoDB clients
    module MongoDB
      module_function

      # removes values for the given documents list
      # NOTE: this is a rough estimation because it's possible to insert
      # many values using different schemas; unfortunately to speed-up the
      # parsing process this is the best guess.
      # TODO: the normalization must be moved at Trace Agent level so that is
      # faster and more accurate
      def normalize_documents(documents)
        return if documents.empty?

        # always take the first element only to keep the resource cardinality
        # and the normalization time low; the document is duplicated to avoid
        # changing the Event query that is shared across the Monitoring system
        document = documents.first.dup

        # delete the unique identifier for this document
        document.delete(:_id)
        document.each do |key, _|
          document[key] = '?'
        end

        document
      end

      # removes values from the given query keys
      def normalize_query(frozen_query)
        # the query is duplicated to avoid changing the Event query that is
        # shared across the Monitoring system
        query = frozen_query.dup
        query.each do |key, _|
          query[key] = '?'
        end

        query
      end
    end
  end
end
