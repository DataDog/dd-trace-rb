module OTelThreadContextTestHelpers
  def read
    raw = _native_read
    return unless raw

    attrs = decode_attrs(raw[:attrs])

    {
      trace_id: raw[:trace_id].unpack1("H*").to_s.to_i(16),
      span_id: raw[:span_id].unpack1("H*").to_s.to_i(16),
      local_root_span_id: attrs[0]&.to_i(16),
      valid: raw[:valid].getbyte(0) == 1,
      attrs: attrs,
    }
  end

  private

  def decode_attrs(raw_attrs)
    attrs = {}
    offset = 0
    size = raw_attrs.bytesize

    while offset + 2 <= size
      key_index = raw_attrs.getbyte(offset)
      value_len = raw_attrs.getbyte(offset + 1)
      break unless key_index && value_len
      break if offset + 2 + value_len > size

      attrs[key_index] = raw_attrs.byteslice(offset + 2, value_len)
      offset += 2 + value_len
    end

    attrs
  end
end
