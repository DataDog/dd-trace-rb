# typed: true
module Datadog
  module Ext
    module Metadata
      # Name of package that was instrumented
      TAG_COMPONENT = 'component'.freeze
      # Role of the service in executing an operation (e.g. client vs server)
      TAG_KIND = 'kind'.freeze
      # Type of operation being performed (e.g. )
      TAG_OPERATION = 'operation'.freeze
      # Hostname of external service interacted with
      TAG_PEER_HOSTNAME = 'peer.hostname'.freeze
      # Name of external service that performed the work
      TAG_PEER_SERVICE = 'peer.service'.freeze
    end
  end
end
