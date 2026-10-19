# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # A wrapper around Seahorse::Client::RequestContext
        class ParsedContext
          # Credential providers whose `account_id` AWS itself established.
          #
          # Both of these populate it from the `AssumedRoleUser.Arn` that STS
          # returned to `AssumeRole` / `AssumeRoleWithWebIdentity`, so the value
          # is AWS stating which account the signing principal belongs to.
          #
          # No other provider qualifies, and the omissions are deliberate: a
          # plain `Aws::Credentials` and the shared-config `account_id` setting
          # take it from local configuration, the environment provider from
          # `AWS_ACCOUNT_ID`, `Aws::SSOCredentials` from the configured
          # `sso_account_id`, `Aws::ProcessCredentials` from a subprocess's
          # `AccountId`, and `Aws::LoginCredentials` from a cached token. Those
          # are all caller-asserted and prove nothing about who owns a resource.
          #
          # Compared by exact class name rather than `is_a?`, because a subclass
          # can override `#refresh` and populate `account_id` from any source,
          # and because the name match needs no AWS constant to be loaded.
          PROVEN_ACCOUNT_ID_PROVIDERS = [
            "Aws::AssumeRoleCredentials",
            "Aws::AssumeRoleWebIdentityCredentials",
          ].freeze

          def initialize(context)
            @context = context
          end

          def safely(attr, fallback = nil)
            public_send(attr)
          rescue
            fallback
          end

          def resource
            "#{service}.#{operation}"
          end

          def operation
            context.operation_name
          end

          def params
            context.params
          end

          def http_response
            context.http_response
          end

          def status_code
            http_response.status_code
          end

          def http_method
            context.http_request.http_method
          end

          def region
            context.client.config.region
          end

          # The account id of the assumed role that signed this request, or nil.
          #
          # Returns a value only for the providers in
          # {PROVEN_ACCOUNT_ID_PROVIDERS}, so the account id always originates
          # from an STS response ARN and never from local configuration. The
          # access key is never inspected.
          def assumed_role_account_id
            provider = signing_credential_provider
            return unless PROVEN_ACCOUNT_ID_PROVIDERS.include?(provider.class.name)

            credentials = resolved_credentials(provider)
            credentials.account_id if credentials.respond_to?(:account_id)
          end

          def retry_attempts
            context.retries
          end

          def path
            context.http_request.endpoint.path
          end

          def host
            context.http_request.endpoint.host
          end

          private

          attr_reader :context

          # The credentials that signed this request.
          #
          # `Aws::Plugins::Sign` signs with `context[:sigv4_credentials]` when a
          # plugin supplied request-scoped credentials (S3 Express session auth,
          # S3 Access Grants) and with `config.credentials` otherwise, so the
          # override is the signing identity whenever it is set.
          def signing_credential_provider
            context[:sigv4_credentials] || context.client.config.credentials
          end

          # Reads the credentials the provider has already resolved, without
          # resolving anything.
          #
          # `Aws::CredentialProvider#credentials` is a plain attribute reader,
          # but both assume-role providers also include
          # `Aws::RefreshingCredentials`, whose override calls
          # `refresh_if_near_expiration!` first. Calling it from here could
          # therefore issue a second `AssumeRole` request on the application's
          # thread in the middle of span annotation, spawn a background refresh
          # thread, and replace the identity that signed this request with a
          # newer one, which would then be tagged as the resource owner.
          #
          # `Aws::RefreshingCredentials` documents `@credentials` as the
          # attribute a provider's `#refresh` populates, and both providers
          # assign an `Aws::Credentials` to it. Reading it is a pure read of
          # state that already exists: no refresh, no network call, no
          # subprocess, and no way to change the signing identity. The SDK
          # exposes no public reader that is guaranteed not to refresh, so this
          # is the narrowest equivalent that is safe to call here.
          #
          # Fails closed: an unset attribute yields nil and nothing is tagged.
          def resolved_credentials(provider)
            return unless provider.instance_variable_defined?(:@credentials)

            provider.instance_variable_get(:@credentials)
          end

          def service
            context.client.class.to_s.split("::")[1].downcase
          end
        end
      end
    end
  end
end
