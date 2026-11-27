require "aws-sdk"
require "tempfile"
require "datadog/tracing/contrib/aws/parsed_context"

RSpec.describe Datadog::Tracing::Contrib::Aws::ParsedContext do
  subject(:parsed_context) { described_class.new(context) }

  let(:credentials) { nil }
  let(:metadata) { {} }
  let(:sigv4_signer) { nil }
  let(:client_config) { double(region: "us-west-2", credentials: credentials, sigv4_signer: sigv4_signer) }

  let(:context) do
    Seahorse::Client::RequestContext.new(
      operation_name: :list_buckets,
      client: double(class: "Aws::S3::Client", config: client_config),
      http_request: Seahorse::Client::Http::Request.new(
        endpoint: URI("http://us-west-2.amazonaws.com.com/"),
      ),
      http_response: Seahorse::Client::Http::Response.new(
        status_code: 200,
      ),
    ).tap { |ctx| metadata.each { |key, value| ctx[key] = value } }
  end

  # The providers parse the account id out of a real (stubbed) STS response.
  def stub_sts_client(operation, account_id: "999988887777", expires_in: 3600)
    client = Aws::STS::Client.new(
      region: "us-east-1",
      credentials: Aws::Credentials.new("stub-akid", "stub-secret"),
      stub_responses: true,
    )
    client.stub_responses(
      operation,
      credentials: {
        access_key_id: "ASIAEXAMPLE",
        secret_access_key: "session-secret",
        session_token: "session-token",
        expiration: Time.now + expires_in,
      },
      assumed_role_user: {
        assumed_role_id: "AROAEXAMPLE:example-session",
        arn: "arn:aws:sts::#{account_id}:assumed-role/example-role/example-session",
      },
    )
    client
  end

  def web_identity_token_file
    file = Tempfile.new("web-identity-token")
    file.write("stub-oidc-token")
    file.flush
    file
  end

  describe "#new" do
    context "given a context with typical values" do
      it do
        is_expected.to have_attributes(
          resource: "s3.list_buckets",
          operation: :list_buckets,
          status_code: 200,
          http_method: "GET",
          region: "us-west-2",
          retry_attempts: 0,
          path: "/",
          http_response: be_kind_of(Seahorse::Client::Http::Response),
        )
      end

      it { expect(parsed_context.host).to include("us-west-2.amazonaws.com") }
    end
  end

  # Pins `aws-sdk-core` behavior that would otherwise stop tagging silently.
  describe "the aws-sdk contract this depends on" do
    it "trusts exactly the two assume-role providers" do
      expect(described_class::PROVEN_ACCOUNT_ID_PROVIDERS).to eq(
        ["Aws::AssumeRoleCredentials", "Aws::AssumeRoleWebIdentityCredentials"],
      )
    end

    it "reads the account id off state, not off a reader that refreshes" do
      expect(Aws::CredentialProvider.instance_method(:credentials).owner)
        .to be(Aws::CredentialProvider)
      expect(Aws::RefreshingCredentials.instance_method(:credentials).owner)
        .to be(Aws::RefreshingCredentials)
      expect(Aws::RefreshingCredentials.private_instance_methods(false))
        .to include(:refresh_if_near_expiration!)
    end

    it "lets the SDK signer expose the provider it signs with" do
      expect(Aws::Sigv4::Signer.public_method_defined?(:credentials_provider)).to be true
    end

    shared_examples "a proven account id provider" do |provider_name|
      let(:provider_class) { Object.const_get(provider_name) }

      it "resolves to a class whose name is exactly #{provider_name}" do
        expect(provider_class).to be_a(Class)
        expect(provider_class.name).to eq(provider_name)
      end

      it "includes Aws::RefreshingCredentials" do
        expect(provider_class.ancestors).to include(Aws::RefreshingCredentials)
      end

      it "exposes the account id STS returned" do
        allow(client_config).to receive(:credentials).and_return(provider)

        expect(parsed_context.assumed_role_account_id).to eq(expected_account_id)
      end
    end

    describe "Aws::AssumeRoleCredentials" do
      let(:expected_account_id) { "999988887777" }
      let(:provider) do
        Aws::AssumeRoleCredentials.new(
          client: stub_sts_client(:assume_role, account_id: expected_account_id),
          role_arn: "arn:aws:iam::#{expected_account_id}:role/example-role",
          role_session_name: "example-session",
        )
      end

      include_examples "a proven account id provider", "Aws::AssumeRoleCredentials"
    end

    describe "Aws::AssumeRoleWebIdentityCredentials" do
      let(:expected_account_id) { "111122223333" }
      let(:token_file) { web_identity_token_file }
      let(:provider) do
        Aws::AssumeRoleWebIdentityCredentials.new(
          client: stub_sts_client(:assume_role_with_web_identity, account_id: expected_account_id),
          role_arn: "arn:aws:iam::#{expected_account_id}:role/example-role",
          role_session_name: "example-session",
          web_identity_token_file: token_file.path,
        )
      end

      after { token_file.close! }

      include_examples "a proven account id provider", "Aws::AssumeRoleWebIdentityCredentials"
    end
  end

  describe "#assumed_role_account_id" do
    subject(:assumed_role_account_id) { parsed_context.assumed_role_account_id }

    context "with an AssumeRole provider" do
      let(:sts_client) { stub_sts_client(:assume_role) }
      let(:credentials) do
        Aws::AssumeRoleCredentials.new(
          client: sts_client,
          role_arn: "arn:aws:iam::999988887777:role/example-role",
          role_session_name: "example-session",
        )
      end

      it "returns the account id STS put in the assumed-role ARN" do
        is_expected.to eq("999988887777")
      end

      it "resolves the credentials exactly once, at construction" do
        allow(sts_client).to receive(:assume_role).and_call_original
        credentials

        parsed_context.assumed_role_account_id
        parsed_context.assumed_role_account_id

        expect(sts_client).to have_received(:assume_role).once
      end

      it "does not refresh even when the resolved credentials are expiring" do
        expiring = stub_sts_client(:assume_role, expires_in: -60)
        provider = Aws::AssumeRoleCredentials.new(
          client: expiring,
          role_arn: "arn:aws:iam::999988887777:role/example-role",
          role_session_name: "example-session",
        )
        allow(expiring).to receive(:assume_role).and_call_original
        allow(client_config).to receive(:credentials).and_return(provider)

        expect(parsed_context.assumed_role_account_id).to eq("999988887777")
        expect(expiring).not_to have_received(:assume_role)
      end

      it "reads the resolved credentials rather than calling #credentials" do
        allow(credentials).to receive(:credentials)

        parsed_context.assumed_role_account_id

        expect(credentials).not_to have_received(:credentials)
      end

      context "when STS returned no assumed-role ARN" do
        let(:sts_client) do
          Aws::STS::Client.new(
            region: "us-east-1",
            credentials: Aws::Credentials.new("stub-akid", "stub-secret"),
            stub_responses: true,
          ).tap do |client|
            client.stub_responses(
              :assume_role,
              credentials: {
                access_key_id: "ASIAEXAMPLE",
                secret_access_key: "session-secret",
                session_token: "session-token",
                expiration: Time.now + 3600,
              },
              assumed_role_user: nil,
            )
          end
        end

        it { is_expected.to be_nil }
      end
    end

    context "with an AssumeRoleWithWebIdentity provider" do
      let(:token_file) { web_identity_token_file }
      let(:sts_client) { stub_sts_client(:assume_role_with_web_identity, account_id: "111122223333") }
      let(:credentials) do
        Aws::AssumeRoleWebIdentityCredentials.new(
          client: sts_client,
          role_arn: "arn:aws:iam::111122223333:role/example-role",
          role_session_name: "example-session",
          web_identity_token_file: token_file.path,
        )
      end

      after { token_file.close! }

      it "returns the account id STS put in the assumed-role ARN" do
        is_expected.to eq("111122223333")
      end

      it "resolves the credentials exactly once, at construction" do
        allow(sts_client).to receive(:assume_role_with_web_identity).and_call_original
        credentials

        parsed_context.assumed_role_account_id
        parsed_context.assumed_role_account_id

        expect(sts_client).to have_received(:assume_role_with_web_identity).once
      end

      it "does not re-read the web identity token file" do
        credentials # resolve once, at construction
        allow(File).to receive(:read).and_call_original

        parsed_context.assumed_role_account_id

        expect(File).not_to have_received(:read).with(token_file.path)
      end
    end

    # These take `account_id` from local config. The gate only reads the class name,
    # so `allocate` stands in for constructors that would reach IMDS, ECS, SSO or disk.
    context "with an untrusted credential source" do
      context "of static credentials carrying an account id" do
        let(:credentials) { Aws::Credentials.new("akid", "secret", nil, account_id: "123456789012") }

        it { is_expected.to be_nil }
      end

      context "of static session credentials carrying an account id" do
        let(:credentials) do
          Aws::Credentials.new("akid", "secret", "session-token", account_id: "123456789012")
        end

        it { is_expected.to be_nil }
      end

      context "of credentials from the AWS_ACCOUNT_ID environment variable" do
        let(:credentials) do
          around_env = Aws::Credentials.new("akid", "secret", "token", account_id: "123456789012")
          around_env.metrics = ["CREDENTIALS_ENV_VARS"]
          around_env
        end

        it { is_expected.to be_nil }
      end

      context "of Aws::SSOCredentials" do
        let(:credentials) { Aws::SSOCredentials.allocate }

        it { is_expected.to be_nil }
      end

      context "of Aws::ProcessCredentials" do
        let(:credentials) { Aws::ProcessCredentials.allocate }

        it { is_expected.to be_nil }
      end

      context "of Aws::InstanceProfileCredentials" do
        let(:credentials) { Aws::InstanceProfileCredentials.allocate }

        it { is_expected.to be_nil }
      end

      context "of Aws::ECSCredentials" do
        let(:credentials) { Aws::ECSCredentials.allocate }

        it { is_expected.to be_nil }
      end

      context "of Aws::SharedCredentials" do
        let(:credentials) { Aws::SharedCredentials.allocate }

        it { is_expected.to be_nil }
      end

      context "of a custom credential provider" do
        let(:credentials) do
          provider = Class.new do
            include Aws::CredentialProvider

            def initialize
              @credentials = Aws::Credentials.new("akid", "secret", "token", account_id: "123456789012")
            end
          end

          provider.new
        end

        it { is_expected.to be_nil }
      end

      context "of a subclass of a proven provider" do
        let(:credentials) do
          subclass = Class.new(Aws::AssumeRoleCredentials) do
            def refresh
              @credentials = Aws::Credentials.new("akid", "secret", "token", account_id: "123456789012")
              @expiration = Time.now + 3600
            end
          end

          subclass.new(
            client: stub_sts_client(:assume_role),
            role_arn: "arn:aws:iam::999988887777:role/example-role",
            role_session_name: "example-session",
          )
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a proven provider that has not resolved credentials" do
      let(:credentials) { Aws::AssumeRoleCredentials.allocate }

      it { is_expected.to be_nil }
    end

    context "with a proven provider whose credentials resolved to nil" do
      let(:credentials) do
        Aws::AssumeRoleCredentials.allocate.tap do |provider|
          allow(provider).to receive(:instance_variable_defined?).with(:@credentials).and_return(true)
        end
      end

      it { is_expected.to be_nil }
    end

    context "with no credentials configured" do
      let(:credentials) { nil }

      it { is_expected.to be_nil }
    end

    context "with request-scoped signing credentials" do
      let(:credentials) do
        Aws::AssumeRoleCredentials.new(
          client: stub_sts_client(:assume_role),
          role_arn: "arn:aws:iam::999988887777:role/example-role",
          role_session_name: "example-session",
        )
      end

      context "that are an untrusted provider" do
        let(:override) { Aws::SSOCredentials.allocate }
        let(:metadata) { {sigv4_credentials: override} }

        it "prefers the credentials that signed and reports nothing" do
          is_expected.to be_nil
        end
      end

      context "that are a proven provider" do
        let(:metadata) do
          {
            sigv4_credentials: Aws::AssumeRoleCredentials.new(
              client: stub_sts_client(:assume_role, account_id: "444455556666"),
              role_arn: "arn:aws:iam::444455556666:role/example-role",
              role_session_name: "example-session",
            ),
          }
        end

        it "reports the signing account, not the client's" do
          is_expected.to eq("444455556666")
        end
      end
    end

    context "with a configured signer" do
      let(:credentials) do
        Aws::AssumeRoleCredentials.new(
          client: stub_sts_client(:assume_role),
          role_arn: "arn:aws:iam::999988887777:role/example-role",
          role_session_name: "example-session",
        )
      end
      let(:signer_credentials) do
        Aws::AssumeRoleCredentials.new(
          client: stub_sts_client(:assume_role, account_id: "444455556666"),
          role_arn: "arn:aws:iam::444455556666:role/example-role",
          role_session_name: "example-session",
        )
      end
      let(:signer_class) { Aws::Sigv4::Signer }
      let(:sigv4_signer) do
        signer_class.new(service: "dynamodb", region: "us-west-2", credentials_provider: signer_credentials)
      end

      context "that is the SDK signer with a proven provider" do
        it "reports the signing account, not the client's" do
          is_expected.to eq("444455556666")
        end

        context "and request-scoped credentials" do
          let(:metadata) { {sigv4_credentials: credentials} }

          it "follows the signer, which the SDK signs with instead" do
            is_expected.to eq("444455556666")
          end
        end
      end

      context "that is the SDK signer with an untrusted provider" do
        let(:signer_credentials) { Aws::Credentials.new("akid", "secret", nil, account_id: "123456789012") }

        it { is_expected.to be_nil }
      end

      context "that is a subclass of the SDK signer" do
        let(:signer_class) { Class.new(Aws::Sigv4::Signer) }

        it { is_expected.to be_nil }
      end

      context "that is a custom signer" do
        let(:sigv4_signer) { double("custom signer", credentials_provider: credentials) }

        it { is_expected.to be_nil }
      end
    end

    context "when the client config does not expose credentials" do
      let(:client_config) { Struct.new(:region).new("us-west-2") }

      it { expect { assumed_role_account_id }.to raise_error(NoMethodError) }

      it "is swallowed by #safely" do
        expect(parsed_context.safely(:assumed_role_account_id)).to be_nil
      end
    end

    context "when reading the credentials raises" do
      before do
        allow(client_config).to receive(:credentials).and_raise(Aws::Errors::MissingCredentialsError)
      end

      it { expect { assumed_role_account_id }.to raise_error(Aws::Errors::MissingCredentialsError) }

      it "is swallowed by #safely" do
        expect(parsed_context.safely(:assumed_role_account_id)).to be_nil
      end
    end
  end

  describe "#input_shape" do
    let(:operation) { Aws::S3::Client.api.operation(:get_object) }

    before { context.operation = operation }

    it "is the operation's input structure" do
      expect(parsed_context.input_shape).to be(operation.input.shape)
    end
  end

  describe "#safely" do
    subject(:attribute) { parsed_context.safely(attribute_name, fallback) }

    let(:attribute_name) { :resource }
    let(:fallback) { "fallback_name" }

    context "when the attribute raises an error" do
      before { allow(parsed_context).to receive(attribute_name).and_raise("Parse error.") }

      it { is_expected.to eq(fallback) }
    end
  end
end
