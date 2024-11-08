#!/usr/bin/env ruby

require 'json'

def requirements
  {
    '$schema' => 'https://raw.githubusercontent.com/DataDog/auto_inject/refs/heads/main/preload_go/cmd/library_requirements_tester/testdata/requirements_schema.json',
    'version' => 1,
    'native_deps' => {
      'glibc' => [
        {
          'arch' => 'x64',
          'supported' => true,
          'min' => '2.27',
          'description' => 'libffi needs memfd_create',
        },
        {
          'arch' => 'arm64',
          'supported' => true,
          'min' => '2.27',
          'description' => 'libffi needs memfd_create',
        },
      ],
      'musl' => [
        {
          'arch' => 'x64',
          'supported' => false,
          'description' => 'no musl build',
        },
        {
          'arch' => 'arm64',
          'supported' => false,
          'description' => 'no musl build',
        },
      ],
    },
    'deny' => [],
  }
end

def write(path)
  File.binwrite(path, JSON.pretty_generate(requirements))
end

if $PROGRAM_NAME == __FILE__
  write(File.join(__dir__, 'requirements.json'))
end
