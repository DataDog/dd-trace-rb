require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/sequel/ext"

RSpec.describe Datadog::Tracing::Contrib::Sequel::Ext do
  it "defines the db name tag" do
    expect(described_class::TAG_DB_NAME).to eq("sequel.db.name")
  end

  it "lists peer.service sources led by the sequel db name tag" do
    expect(described_class::PEER_SERVICE_SOURCES).to eq(
      [
        "sequel.db.name",
        "db.instance",
        "network.destination.name",
        "peer.hostname",
        "out.host",
      ],
    )
  end
end
