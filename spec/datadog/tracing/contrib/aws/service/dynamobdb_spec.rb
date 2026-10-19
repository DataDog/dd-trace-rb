# frozen_string_literal: true

require "aws-sdk"
require "datadog/tracing/contrib/aws/parsed_context"
require "datadog/tracing/contrib/aws/service/dynamodb"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::DynamoDB do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:dynamodb) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with table_name provided" do
    let(:table_name) { "example-table" }
    let(:params) { {table_name: table_name} }

    it "sets the table_name tag" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, table_name)
    end
  end

  context "with no table_name provided" do
    it "does not set the table_name tag" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, nil)
    end
  end

  describe "#add_owner_tags" do
    subject(:add_owner_tags) { dynamodb.add_owner_tags(span, params, context) }

    let(:context) { instance_double(Datadog::Tracing::Contrib::Aws::ParsedContext) }
    let(:account_id) { "123456789012" }
    let(:status_code) { 200 }
    let(:host) { "dynamodb.us-east-1.amazonaws.com" }
    let(:params) { {table_name: "example-table"} }

    before do
      allow(context).to receive(:safely).with(:assumed_role_account_id).and_return(account_id)
      allow(context).to receive(:safely).with(:status_code).and_return(status_code)
      allow(context).to receive(:safely).with(:host).and_return(host)
    end

    context "with a bare table name and a resolved account id" do
      it "sets the aws_account tag" do
        add_owner_tags
        expect(span).to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "with a bare table name using every allowed character" do
      let(:params) { {table_name: "Example_table.v2-prod"} }

      it "sets the aws_account tag" do
        add_owner_tags
        expect(span).to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "with a table name at the length bounds" do
      it "sets the aws_account tag at 3 and 255 characters" do
        [3, 255].each do |length|
          dynamodb.add_owner_tags(span, {table_name: "a" * length}, context)
        end

        expect(span).to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, "123456789012").twice
      end

      it "does not set the aws_account tag outside those bounds" do
        [2, 256].each do |length|
          dynamodb.add_owner_tags(span, {table_name: "a" * length}, context)
        end

        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "with a table ARN" do
      let(:params) { {table_name: "arn:aws:dynamodb:us-east-1:999988887777:table/example-table"} }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end

      it "does not read the credentials" do
        add_owner_tags
        expect(context).not_to have_received(:safely)
      end
    end

    context "with no table name" do
      let(:params) { {} }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end

      it "does not read the credentials" do
        add_owner_tags
        expect(context).not_to have_received(:safely)
      end
    end

    context "with a non-string table name" do
      let(:params) { {table_name: :example_table} }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    # A bare name only names a table in the signing account once DynamoDB has
    # resolved it there, so the response has to be a success from AWS. The full
    # status and endpoint matrix lives with the shared gate, in the spec for
    # `Service::Base#aws_confirmed_response?`.
    context "when the request failed" do
      let(:status_code) { 400 }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end

      it "does not read the credentials" do
        add_owner_tags
        expect(context).not_to have_received(:safely).with(:assumed_role_account_id)
      end
    end

    context "when the request was denied" do
      let(:status_code) { 403 }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    # DynamoDB Local and LocalStack resolve the same bare name in a local store
    # that has no AWS account behind it.
    context "when a DynamoDB-compatible endpoint answers 2xx" do
      let(:host) { "localhost" }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end

      it "does not read the credentials" do
        add_owner_tags
        expect(context).not_to have_received(:safely).with(:assumed_role_account_id)
      end
    end

    context "when the endpoint is an AWS lookalike domain" do
      let(:host) { "dynamodb.us-east-1.amazonaws.com.example.net" }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "when the partition list is unavailable" do
      before { allow(Datadog::Tracing::Contrib::Aws::Service::Base).to receive(:aws_dotted_dns_suffixes).and_return([].freeze) }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "with no account id resolved" do
      let(:account_id) { nil }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "with a malformed account id" do
      [
        "",
        "1234",
        "1234567890123",
        "12345678901",
        "12345678901a",
        " 123456789012",
        "123456789012 ",
        "123456789012\n",
        "1234-5678-9012",
        "arn:aws:iam::123456789012:root",
      ].each do |malformed|
        context "of #{malformed.inspect}" do
          let(:account_id) { malformed }

          it "does not set the aws_account tag" do
            add_owner_tags
            expect(span).not_to have_received(:set_tag)
              .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
          end
        end
      end
    end

    context "with a numeric account id" do
      let(:account_id) { 123456789012 }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end
  end
end
