require "json"
require "datadog/di/snapshot_encoder"

# Payload builders and encoded-tree checks shared by the
# Datadog::DI::SnapshotEncoder specs.
module SnapshotEncoderHelpers
  # Returns a snapshot payload with the envelope members the snapshot
  # builder produces and the given captures.
  def snapshot_payload(captures:, probe_id: "probe-1")
    {
      service: "encoder-spec",
      debugger: {
        type: "snapshot",
        snapshot: {
          id: "00000000-0000-0000-0000-000000000001",
          timestamp: 1_700_000_000_000,
          evaluationErrors: [],
          probe: {id: probe_id, version: 0, location: {method: "run", type: "Target"}},
          language: "ruby",
          stack: [{fileName: "/app/target.rb", function: "run", lineNumber: 10}],
          captures: captures,
        },
      },
      duration: 0,
      host: nil,
      logger: {name: "/app/target.rb", method_name: "run", thread_name: "main", thread_id: nil},
      runtime_id: "00000000-0000-0000-0000-000000000002",
      "dd.trace_id": nil,
      "dd.span_id": nil,
      ddsource: "dd_debugger",
      message: nil,
      timestamp: 1_700_000_000_000,
    }
  end

  # Returns the payload of a method probe whose return capture set holds
  # the given return value.
  def return_payload(return_value, entry_arguments: {})
    snapshot_payload(captures: {
      entry: {arguments: entry_arguments},
      return: {arguments: {"@return": return_value}, throwable: nil},
    })
  end

  # Returns a serialized String captured value.
  def string_value(text)
    {type: "String", value: text}
  end

  # Returns a serialized Array captured value.
  def array_value(elements, **extra)
    {type: "Array", elements: elements}.merge(extra)
  end

  # Builds the encoded tree of +payload+.
  def build_tree(payload)
    Datadog::DI::SnapshotEncoder::TreeBuilder.new.build(payload)
  end

  # Writes the JSON text of the subtree under +node+.
  def emit(node)
    Datadog::DI::SnapshotEncoder::Emitter.new.emit(node)
  end

  # Returns every container node of the tree under +root+, in pre-order.
  def container_nodes(root)
    found = []
    pending = [root]
    until pending.empty?
      node = pending.shift
      next unless node.is_a?(Datadog::DI::SnapshotEncoder::ContainerNode)

      found << node
      pending.concat(node.children)
    end
    found
  end

  # Returns the byte size of +node+'s JSON text truncated to its first
  # KEPT_ELEMENT_COUNT children, written from the emitted children.
  def truncated_json_size(node)
    kept = Datadog::DI::SnapshotEncoder::KEPT_ELEMENT_COUNT
    if node.is_a?(Datadog::DI::SnapshotEncoder::ObjectNode)
      members = node.children.first(kept).each_with_index.map do |child, index|
        "#{node.member_names_json[index]}:#{emit(child)}"
      end
      "{#{members.join(",")}}".bytesize
    else
      "[#{node.children.first(kept).map { |child| emit(child) }.join(",")}]".bytesize
    end
  end

  # Expects every container node under +root+ to record the byte sizes of
  # its emitted JSON text and of its text truncated to KEPT_ELEMENT_COUNT
  # children.
  def expect_exact_sizes(root)
    container_nodes(root).each do |node|
      expect(node.size).to eq(emit(node).bytesize)
      expect(node.prefix_size).to eq(truncated_json_size(node))
    end
  end
end
