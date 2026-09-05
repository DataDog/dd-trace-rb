#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal zip extractor for the pinned vale style archives. The CI job
# containers ship without unzip, but always ship ruby, and zlib inflates
# raw deflate streams (window bits -15).

def die(message)
  abort "extract_zip: #{message}"
end

require "zlib"

archive, dest = ARGV
die("usage: extract_zip.rb ARCHIVE DEST") if archive.nil? || dest.nil?
require "fileutils"

blob = File.binread(archive)
die("not a zip archive: #{archive}") unless blob

# The End of Central Directory record ends the archive; a trailing comment
# makes its offset variable, so scan back for its signature.
eocd = blob.rindex("PK\x05\x06".b)
die("no End of Central Directory record in #{archive}") unless eocd

entry_count = blob[eocd + 10, 2].unpack1("v")
cd_offset = blob[eocd + 16, 4].unpack1("V")
if entry_count == 0xFFFF || cd_offset == 0xFFFFFFFF
  die("zip64 archives are not supported: #{archive}")
end

pos = cd_offset
entry_count.times do
  header = blob[pos, 46]
  die("corrupt central directory entry at #{pos}") if header.nil? || header[0, 4] != "PK\x01\x02".b

  method = header[10, 2].unpack1("v")
  compressed_size = header[20, 4].unpack1("V")
  uncompressed_size = header[24, 4].unpack1("V")
  name_len, extra_len, comment_len = header[28, 6].unpack("vvv")
  external_attrs, local_offset = header[38, 8].unpack("VV")
  name = blob[pos + 46, name_len]
  pos += 46 + name_len + extra_len + comment_len

  # The local header's name and extra fields may differ in length from the
  # central directory's, so its own sizes locate the entry data.
  local = blob[local_offset, 30]
  die("corrupt local header for #{name}") if local.nil? || local[0, 4] != "PK\x03\x04".b
  local_name_len, local_extra_len = local[26, 4].unpack("vv")
  data_offset = local_offset + 30 + local_name_len + local_extra_len

  path = File.expand_path(name, dest)
  die("unsafe entry name in #{archive}: #{name}") unless path.start_with?("#{File.expand_path(dest)}/")

  if name.end_with?("/")
    FileUtils.mkdir_p(path)
    next
  end

  data = blob[data_offset, compressed_size]
  case method
  when 0
    # stored
  when 8
    data = Zlib::Inflate.new(-15).inflate(data)
  else
    die("unsupported compression method #{method} for #{name}")
  end
  die("size mismatch for #{name}: expected #{uncompressed_size} bytes, got #{data.bytesize}") unless
    data.bytesize == uncompressed_size

  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, data)

  mode = external_attrs >> 16
  File.chmod(mode & 0o7777, path) unless mode.zero?
end
