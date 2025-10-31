#!/bin/bash
set -e

# Configuration - Set these paths to match your local setup
# You can override these by setting environment variables before running the script:
# 
# Example usage with custom paths:
# export LIBDATADOG_PATH="/path/to/your/libdatadog"
# export DD_TRACE_RB_PATH="/path/to/your/dd-trace-rb"
# ./setup_ffe.sh
#
LIBDATADOG_PATH="${LIBDATADOG_PATH:-$HOME/dd/libdatadog}"
DD_TRACE_RB_PATH="${DD_TRACE_RB_PATH:-$HOME/dd/dd-trace-rb}"
CARGO_BIN="${CARGO_BIN:-$HOME/.cargo/bin/cargo}"

# Detect architecture for build directory
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
KERNEL_VERSION=$(uname -r | cut -d. -f1)
BUILD_ARCH="${ARCH}-${OS}-${KERNEL_VERSION}"

echo "🚀 Setting up FFE (Feature Flags & Experimentation) for dd-trace-rb"
echo "📍 Using libdatadog path: ${LIBDATADOG_PATH}"
echo "📍 Using dd-trace-rb path: ${DD_TRACE_RB_PATH}"
echo "📍 Detected build architecture: ${BUILD_ARCH}"

# Step 1: Build libdatadog
echo "📦 Step 1: Building libdatadog..."
cd "${LIBDATADOG_PATH}"
git checkout sameerank/FFL-1284-Create-datadog-ffe-ffi-crate
"${CARGO_BIN}" build --release

echo "✅ Step 1 completed: libdatadog built successfully"

# Step 2: Set Up dd-trace-rb Build Environment
echo "🔧 Step 2: Setting up dd-trace-rb build environment..."
cd "${DD_TRACE_RB_PATH}"
git checkout sameerank/FFL-1273-Bindings-for-ffe-in-openfeature-provider

# Create local build directory structure
echo "Creating directory structure..."
mkdir -p "my-libdatadog-build/${BUILD_ARCH}/lib"
mkdir -p "my-libdatadog-build/${BUILD_ARCH}/include/datadog"
mkdir -p my-libdatadog-build/pkgconfig

# Copy ALL FFI libraries (this gives us everything we need!)
echo "Copying all FFI libraries..."
cp "${LIBDATADOG_PATH}/target/release/libddcommon_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_ffe_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_crashtracker_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libddsketch_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_library_config_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_profiling_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"

# Generate the headers we need, being strategic about what we include
echo "Generating headers..."
cd "${LIBDATADOG_PATH}"
cbindgen ddcommon-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/common.h"
cbindgen datadog-ffe-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
cbindgen datadog-crashtracker-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
cbindgen ddsketch-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
cbindgen datadog-library-config-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"

# Add ddog_VoidResult to common.h since it's needed by crashtracker but not included
cd "${DD_TRACE_RB_PATH}"
echo "Adding ddog_VoidResult to common.h..."
sed -i.bak '/^#endif.*DDOG_COMMON_H/i\
\
/**\
 * A generic result type for when an operation may fail,\
 * but there'\''s nothing to return in the case of success.\
 */\
typedef enum ddog_VoidResult_Tag {\
  DDOG_VOID_RESULT_OK,\
  DDOG_VOID_RESULT_ERR,\
} ddog_VoidResult_Tag;\
\
typedef struct ddog_VoidResult {\
  ddog_VoidResult_Tag tag;\
  union {\
    struct {\
      struct ddog_Error err;\
    };\
  };\
} ddog_VoidResult;\
\
' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/common.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/common.h.bak"

# Remove specific conflicting types from crashtracker.h that are already in common.h
echo "Removing duplicate types from crashtracker.h..."
sed -i.bak1 '/typedef enum ddog_VoidResult_Tag {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak2 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak3 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak4 '/typedef struct ddog_Slice_CChar {/,/} ddog_Slice_CChar;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak5 '/typedef struct ddog_Vec_Tag {/,/} ddog_Vec_Tag;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak6 '/typedef struct ddog_StringWrapper {/,/} ddog_StringWrapper;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak7 '/typedef struct ddog_Slice_CChar ddog_CharSlice;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak8 '/typedef struct ddog_Endpoint ddog_Endpoint;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
sed -i.bak9 '/typedef struct ddog_Tag ddog_Tag;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"

# Fix the internal duplication issue within crashtracker.h where cbindgen generates the same enum twice
echo "Fixing internal duplicates in crashtracker.h..."
# Remove the second occurrence of ddog_crasht_StacktraceCollection enum (lines 57-71 based on error)
sed -i.bak10 '57,71{/typedef enum ddog_crasht_StacktraceCollection {/,/} ddog_crasht_StacktraceCollection;/d;}' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"

rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h.bak"*

# Remove duplicates from ddsketch.h too
echo "Removing duplicate types from ddsketch.h..."
sed -i.bak1 '/typedef enum ddog_VoidResult_Tag {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
sed -i.bak2 '/typedef struct ddog_VoidResult {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
sed -i.bak3 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
sed -i.bak4 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h.bak"*

# Remove duplicates from datadog_ffe.h too
echo "Removing duplicate types from datadog_ffe.h..."
sed -i.bak1 '/typedef enum ddog_VoidResult_Tag {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
sed -i.bak2 '/typedef struct ddog_VoidResult {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
sed -i.bak3 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
sed -i.bak4 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h.bak"*

# Remove duplicates from library-config.h too
echo "Removing duplicate types from library-config.h..."
sed -i.bak1 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak2 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak3 '/typedef struct ddog_Slice_CChar {/,/} ddog_Slice_CChar;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak4 '/typedef struct ddog_Slice_CChar ddog_CharSlice;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h.bak"*

# Create minimal stub headers for libraries we're linking but don't actively use
echo "Creating minimal stub headers for unused linked libraries..."

# profiling.h - minimal stub  
cat > "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h" << 'EOF'
#ifndef DDOG_PROFILING_H
#define DDOG_PROFILING_H

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "common.h"

// Minimal declarations for profiling functionality
// Ruby bindings don't need full profiling API, just enough to link

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// Stub function declarations - can be extended as needed

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* DDOG_PROFILING_H */
EOF

# No more stub headers needed! We have real ones from cbindgen

# Create pkg-config file for all FFI libraries
echo "Creating pkg-config file..."
CURRENT_DIR=$(pwd)
cat > my-libdatadog-build/pkgconfig/datadog_profiling_with_rpath.pc << EOF
prefix=${CURRENT_DIR}/my-libdatadog-build
exec_prefix=\${prefix}
libdir=\${exec_prefix}/${BUILD_ARCH}/lib
includedir=\${prefix}/${BUILD_ARCH}/include

Name: datadog_profiling_with_rpath
Description: Datadog libdatadog library (with rpath) - Full FFI build
Version: 22.1.0
Libs: -L\${libdir} -ldatadog_ffe_ffi -ldatadog_crashtracker_ffi -lddsketch_ffi -ldatadog_library_config_ffi -ldatadog_profiling_ffi -Wl,-rpath,\${libdir}
Cflags: -I\${includedir}
EOF

echo "✅ Step 2 completed: Build environment set up"

# Step 3: Compile Ruby Extension
echo "🔨 Step 3: Compiling Ruby extension..."

# Set PKG_CONFIG_PATH to find our custom build
export PKG_CONFIG_PATH="$(pwd)/my-libdatadog-build/pkgconfig:$PKG_CONFIG_PATH"
echo "PKG_CONFIG_PATH set to: $PKG_CONFIG_PATH"

# Compile the Ruby extension
cd ext/libdatadog_api
echo "Generating Makefile..."
ruby extconf.rb
echo "Compiling extension..."
make
echo "Installing extension..."
cp libdatadog_api.*.bundle ../../lib/
echo "Cleaning up build artifacts..."
make clean
rm -f Makefile
cd ../..

echo "✅ Step 3 completed: Ruby extension built and installed"

# Step 4: Test and Verify
echo "🧪 Step 4: Testing FFE functionality..."
echo "🔍 Verifying functionality..."
bundle exec ruby -e "
require './lib/datadog/open_feature'
puts 'FFE supported: ' + Datadog::OpenFeature::Binding.supported?.to_s
puts 'Build successful!' if Datadog::OpenFeature::Binding.supported?
"

echo "🎯 Testing end-to-end functionality..."
bundle exec ruby -e "
require './lib/datadog/open_feature'

# Use Universal Flag Configuration JSON format
config_json = '{
  \"data\": {
    \"type\": \"universal-flag-configuration\",
    \"id\": \"1\",
    \"attributes\": {
      \"createdAt\": \"2024-04-17T19:40:53.716Z\",
      \"format\": \"SERVER\",
      \"environment\": { \"name\": \"test\" },
      \"flags\": {
        \"test_flag\": {
          \"key\": \"test_flag\",
          \"enabled\": true,
          \"variationType\": \"STRING\",
          \"variations\": { \"control\": { \"key\": \"control\", \"value\": \"control_value\" } },
          \"allocations\": [{
            \"key\": \"rollout\",
            \"splits\": [{ \"variationKey\": \"control\", \"shards\": [] }],
            \"doLog\": false
          }]
        }
      }
    }
  }
}'

begin
  config = Datadog::OpenFeature::Binding::Configuration.new(config_json)
  context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user')
  assignment = Datadog::OpenFeature::Binding.get_assignment(config, 'test_flag', context)
  puts 'Assignment result: ' + assignment.inspect
  puts '🎉 FFE end-to-end functionality verified!'
rescue => e
  puts 'Error: ' + e.message
end
"

echo "📋 Running RSpec tests..."
bundle exec rspec spec/datadog/open_feature/binding_spec.rb

echo "✅ Step 4 completed: FFE functionality verified"

# Step 5: Clean up build directory
echo "🧹 Step 5: Cleaning up build directory..."
rm -rf my-libdatadog-build

echo "✅ All steps completed successfully!"
