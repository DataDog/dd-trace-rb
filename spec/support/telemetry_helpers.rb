module TelemetryHelpers
  module ClassMethods
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Yield every leaf (non-settings) option in the live settings tree.
  def each_leaf_option(settings, &block)
    settings.class.options.each_key do |name|
      option = settings.send(:resolve_option, name)
      if option.settings?
        each_leaf_option(option.get, &block)
      else
        block.call(option)
      end
    end
  end

  RSpec.shared_examples "telemetry event with no attributes" do
    it "all event instances to the same" do
      event1 = described_class.new
      event2 = described_class.new
      expect(event1).to eq(event2)
      expect(event1.hash).to eq(event2.hash)
    end
  end
end
