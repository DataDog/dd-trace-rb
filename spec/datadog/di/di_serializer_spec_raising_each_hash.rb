class DISerializerSpecRaisingEachHash < Hash
  def each
    raise "Arrgh!"
  end
end
