# frozen_string_literal: true

module Datadog
  module Kit
    # Tracking identity via traces
    module Identity
      # Attach user information to the trace
      #
      # @param trace [TraceOperation] Trace to attach data to.
      # @param id [String] Mandatory. Username or client id extracted
      #   from the access token or Authorization header in the inbound request
      #   from outside the system.
      # @param email [String] Email of the authenticated user associated
      #   to the trace.
      # @param name [String] User-friendly name. To be displayed in the
      #   UI if set.
      # @param session_id [String] Session ID of the authenticated user.
      # @param role [String] Actual/assumed role the client is making
      #   the request under extracted from token or application security
      #   context.
      # @param scope [String] Scopes or granted authorities the client
      #   currently possesses extracted from token or application security
      #   context. The value would come from the scope associated with an OAuth
      #   2.0 Access Token or an attribute value in a SAML 2.0 Assertion.
      # @param others [Hash<Symbol, String>] Additional free-form
      #   user information to attach to the trace.
      #
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def self.set_user(trace, id:, email: nil, name: nil, session_id: nil, role: nil, scope: nil, **others)
        raise ArgumentError, 'missing required key: :id' if id.nil?

        # enforce types

        raise TypeError, ':id must be a String'         unless id.is_a?(String)
        raise TypeError, ':email must be a String'      unless email.nil? || email.is_a?(String)
        raise TypeError, ':name must be a String'       unless name.nil? || name.is_a?(String)
        raise TypeError, ':session_id must be a String' unless session_id.nil? || session_id.is_a?(String)
        raise TypeError, ':role must be a String'       unless role.nil? || role.is_a?(String)
        raise TypeError, ':scope must be a String'      unless scope.nil? || scope.is_a?(String)

        others.each do |k, v|
          raise TypeError, "#{k.inspect} must be a String" unless v.nil? || v.is_a?(String)
        end

        # set tags once data is known consistent

        trace.set_tag('usr.id', id)
        trace.set_tag('usr.email', email)           unless email.nil?
        trace.set_tag('usr.name', name)             unless name.nil?
        trace.set_tag('usr.session_id', session_id) unless session_id.nil?
        trace.set_tag('usr.role', role)             unless role.nil?
        trace.set_tag('usr.scope', scope)           unless scope.nil?

        others.each do |k, v|
          trace.set_tag("usr.#{k}", v) unless v.nil?
        end

        if Datadog.configuration.appsec.enabled
          user = OpenStruct.new(id: id)
          ::Datadog::AppSec::Instrumentation.gateway.push('identity.set_user', user)
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity
    end
  end
end
