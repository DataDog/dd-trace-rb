# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/dynamodb"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::DynamoDB do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:dynamodb) { described_class.new }
  let(:ext) { Datadog::Tracing::Contrib::Aws::Ext }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with table_name provided" do
    let(:table_name) { "example-table" }
    let(:params) { {table_name: table_name} }

    it "sets the table_name tag" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, table_name)
    end

    it "sets the aws.table.name tag" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, table_name)
    end

    it "does not set an account it was not given" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end

    it "does not set an ARN it was not given" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end
  end

  context "with no table_name provided" do
    it "does not set the table_name tag" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, nil)
    end

    it "does not set the aws.table.name tag" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
    end

    it "does not set the aws.table.arn tag" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end
  end

  context "with a table ARN provided as table_name" do
    let(:table_name) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable" }
    let(:params) { {table_name: table_name} }

    it "resolves the table name out of the ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, "MyTable")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, "MyTable")
    end

    it "sets the owning account from the ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end

    it "reports the ARN exactly as the request supplied it" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_ARN, table_name)
    end
  end

  context "with a table ARN whose Region differs from the client's" do
    let(:table_name) { "arn:aws:dynamodb:eu-central-1:999999999999:table/CrossRegionTable" }
    let(:params) { {table_name: table_name} }

    it "reports the target's name, account and complete ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, "CrossRegionTable")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, "CrossRegionTable")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "999999999999")
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_ARN, table_name)
    end

    it "retains the target Region inside the ARN rather than in a tag of its own" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_ARN, /:eu-central-1:/)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_REGION, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_REGION, anything)
    end
  end

  context "with a GovCloud table ARN provided as table_name" do
    let(:table_name) { "arn:aws-us-gov:dynamodb:us-gov-west-1:123456789012:table/MyTable" }
    let(:params) { {table_name: table_name} }

    it "resolves the table name, account and ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, "MyTable")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_ARN, table_name)
    end
  end

  context "with a China table ARN provided as table_name" do
    let(:table_name) { "arn:aws-cn:dynamodb:cn-north-1:123456789012:table/MyTable" }
    let(:params) { {table_name: table_name} }

    it "resolves the table name, account and ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, "MyTable")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_ARN, table_name)
    end
  end

  context "with a global table ARN provided as table_name" do
    let(:table_name) { "arn:aws:dynamodb::123456789012:global-table/MyTable" }
    let(:params) { {table_name: table_name} }

    it "keeps the value in the legacy tag but reports no table name" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, table_name)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
    end

    it "claims neither an account nor a table ARN" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end
  end

  context "with a malformed ARN provided as table_name" do
    let(:table_name) { "arn:aws:dynamodb:us-east-1:oops:table/MyTable" }
    let(:params) { {table_name: table_name} }

    it "keeps the value in the legacy tag but reports no table name" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, table_name)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
    end

    it "does not invent an account or an ARN" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end
  end

  context "with another service's ARN provided as table_name" do
    let(:table_name) { "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream" }
    let(:params) { {table_name: table_name} }

    it "keeps the value in the legacy tag and claims no name, account or ARN" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, table_name)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end
  end

  describe "with an ARN that is not a table ARN" do
    [
      ["a stream ARN", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/stream/2024-01-01T00:00:00.000"],
      ["an index ARN", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/index/MyIndex"],
      ["a trailing separator", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/"],
      ["a colon after the resource type", "arn:aws:dynamodb:us-east-1:123456789012:table:MyTable"],
      ["a colon inside the name", "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable:extra"],
      ["no Region", "arn:aws:dynamodb::123456789012:table/MyTable"],
      ["no account", "arn:aws:dynamodb:us-east-1::table/MyTable"],
    ].each do |description, value|
      context "with #{description}" do
        let(:params) { {table_name: value} }

        it "keeps the value in the legacy tag and claims no identity" do
          dynamodb.add_tags(span, params)
          expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, value)
          expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
          expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
          expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
        end

        it "does not report the table the subresource belongs to" do
          dynamodb.add_tags(span, params)
          expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, "MyTable")
        end
      end
    end
  end

  context "with an empty table_name" do
    let(:params) { {table_name: ""} }

    it "writes the legacy tag but not the new one" do
      dynamodb.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, "")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
    end
  end

  context "with a table_name whose bytes are invalid in its encoding" do
    let(:table_name) do
      (+"arn:aws:dynamodb:us-east-1:123456789012:table/My\xFFTable").force_encoding("UTF-8")
    end
    let(:params) { {table_name: table_name} }

    it "passes the value through without raising" do
      expect { dynamodb.add_tags(span, params) }.not_to raise_error
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, table_name)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
    end

    it "reports no table name" do
      dynamodb.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, anything)
    end
  end

  context "with a non-string table_name" do
    let(:params) { {table_name: :orders} }

    it "writes the legacy tag and claims no ARN or account" do
      expect { dynamodb.add_tags(span, params) }.not_to raise_error
      expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, :orders)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_TABLE_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  describe "with a bare name that resembles the ARN prefix" do
    ["arn", "arn-table", "arnold", "arn.orders"].each do |value|
      context "with #{value.inspect}" do
        let(:params) { {table_name: value} }

        it "reports the name in both tags" do
          dynamodb.add_tags(span, params)
          expect(span).to have_received(:set_tag).with(ext::TAG_TABLE_NAME, value)
          expect(span).to have_received(:set_tag).with(ext::TAG_AWS_TABLE_NAME, value)
        end
      end
    end
  end
end
