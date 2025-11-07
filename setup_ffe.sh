#!/bin/bash
set -e

# Function to clean up on script exit (success or failure)
cleanup_on_exit() {
  echo "🧹 Performing cleanup..."
  cd "${DD_TRACE_RB_PATH}" 2>/dev/null || cd "$(pwd)"
  rm -rf my-libdatadog-build
  rm -f setup_ffe.sh.patch
  find . -name "*.bak*" -delete 2>/dev/null || true
  
  # Clean up Ruby extension build artifacts in tmp/ if they exist
  if [ -d "tmp" ]; then
    find tmp -name "*libdatadog_api*" -delete 2>/dev/null || true
    find tmp -type d -empty -delete 2>/dev/null || true
  fi
  
  # Reset environment variables
  unset PKG_CONFIG_PATH 2>/dev/null || true
  unset LIBDATADOG_VENDOR_OVERRIDE 2>/dev/null || true
}

# Set up cleanup trap to run on script exit
trap cleanup_on_exit EXIT

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

# Detect architecture using Ruby's platform detection
BUILD_ARCH=$(ruby -e 'puts Gem::Platform.local.to_s')
export DD_RUBY_PLATFORM="$BUILD_ARCH"

# Skip profiling native extension (complex build) but keep profiling FFI libs for compatibility
export DD_PROFILING_NO_EXTENSION=true

echo "🚀 Setting up FFE (Feature Flags & Experimentation) for dd-trace-rb"
echo "📍 Using libdatadog path: ${LIBDATADOG_PATH}"
echo "📍 Using dd-trace-rb path: ${DD_TRACE_RB_PATH}"
echo "📍 Detected Ruby platform: ${BUILD_ARCH}"
echo "📍 DD_RUBY_PLATFORM set to: ${DD_RUBY_PLATFORM}"
echo "📍 DD_PROFILING_NO_EXTENSION=true (profiling native extension disabled, but headers/libs included)"

# Clean up any previous build artifacts first
echo "🧹 Cleaning up any previous build artifacts..."
cleanup_on_exit

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
mkdir -p "my-libdatadog-build/${BUILD_ARCH}/pkgconfig"

# Copy all FFI libraries
echo "Copying FFI libraries..."
cp "${LIBDATADOG_PATH}/target/release/libddcommon_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_ffe_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_crashtracker_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/liblibdd_ddsketch_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/liblibdd_library_config_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"
cp "${LIBDATADOG_PATH}/target/release/libdatadog_profiling_ffi."* "my-libdatadog-build/${BUILD_ARCH}/lib/"

# Generate the headers we need, being strategic about what we include
echo "Generating headers..."
cd "${LIBDATADOG_PATH}"
cbindgen ddcommon-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/common.h"
cbindgen datadog-ffe-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
cbindgen datadog-crashtracker-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/crashtracker.h"
cbindgen libdd-ddsketch-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/ddsketch.h"
cbindgen libdd-library-config-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
cbindgen datadog-profiling-ffi --output "${DD_TRACE_RB_PATH}/my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"

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
sed -i.bak5 '/struct ddog_Error {/,/};/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
sed -i.bak6 '/struct ddog_ffe_Vec_U8 {/,/};/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/datadog_ffe.h.bak"*

# Remove duplicates from library-config.h too
echo "Removing duplicate types from library-config.h..."
sed -i.bak1 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak2 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak3 '/typedef struct ddog_Slice_CChar {/,/} ddog_Slice_CChar;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
sed -i.bak4 '/typedef struct ddog_Slice_CChar ddog_CharSlice;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/library-config.h.bak"*

# Remove duplicates from profiling.h too
echo "Removing duplicate types from profiling.h..."
sed -i.bak1 '/typedef enum ddog_VoidResult_Tag {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak2 '/typedef struct ddog_VoidResult {/,/} ddog_VoidResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak3 '/typedef struct ddog_Vec_U8 {/,/} ddog_Vec_U8;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak4 '/typedef struct ddog_Error {/,/} ddog_Error;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak5 '/typedef struct ddog_Tag ddog_Tag;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak6 '/typedef struct ddog_Slice_CChar {/,/} ddog_Slice_CChar;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak7 '/typedef struct ddog_Slice_CChar ddog_CharSlice;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak8 '/typedef struct ddog_Vec_Tag {/,/} ddog_Vec_Tag;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak9 '/typedef struct ddog_Timespec {/,/} ddog_Timespec;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak10 '/typedef struct ddog_StringWrapper {/,/} ddog_StringWrapper;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak11 '/typedef enum ddog_StringWrapperResult_Tag {/,/} ddog_StringWrapperResult_Tag;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak12 '/typedef struct ddog_StringWrapperResult {/,/} ddog_StringWrapperResult;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"

# Fix internal duplicates within profiling.h itself
sed -i.bak13 '/typedef struct ddog_prof_EncodedProfile ddog_prof_EncodedProfile;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak14 '/typedef struct OpaqueStringId OpaqueStringId;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
sed -i.bak15 '/typedef struct ddog_prof_StringId ddog_prof_StringId;/d' "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h"
rm -f "my-libdatadog-build/${BUILD_ARCH}/include/datadog/profiling.h.bak"*

# Create pkg-config file for all FFI libraries
echo "Creating pkg-config file..."
CURRENT_DIR=$(pwd)
cat > "my-libdatadog-build/${BUILD_ARCH}/pkgconfig/datadog_profiling_with_rpath.pc" << EOF
prefix=${CURRENT_DIR}/my-libdatadog-build/${BUILD_ARCH}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: datadog_profiling_with_rpath
Description: Datadog libdatadog library (with rpath) - Full FFI build with profiling native extension disabled
Version: 22.1.0
Libs: -L\${libdir} -ldatadog_ffe_ffi -ldatadog_crashtracker_ffi -llibdd_ddsketch_ffi -llibdd_library_config_ffi -ldatadog_profiling_ffi -Wl,-rpath,\${libdir}
Cflags: -I\${includedir}
EOF

echo "✅ Step 2 completed: Build environment set up"

# Step 3: Compile Ruby Extension
echo "🔨 Step 3: Compiling Ruby extension..."

# Set environment variables for Ruby extension build
export PKG_CONFIG_PATH="$(pwd)/my-libdatadog-build/${BUILD_ARCH}/pkgconfig:$PKG_CONFIG_PATH"
export LIBDATADOG_VENDOR_OVERRIDE="$(pwd)/my-libdatadog-build/"
echo "PKG_CONFIG_PATH set to: $PKG_CONFIG_PATH"
echo "LIBDATADOG_VENDOR_OVERRIDE set to: $LIBDATADOG_VENDOR_OVERRIDE"

# Compile the Ruby extension using rake-compiler
echo "Compiling libdatadog_api extension using rake-compiler..."
LIBDATADOG_COMPILE_TASK=$(bundle exec rake -T | grep "compile:libdatadog_api\." | head -1 | awk '{print $2}')
echo "Using rake task: ${LIBDATADOG_COMPILE_TASK}"
bundle exec rake "${LIBDATADOG_COMPILE_TASK}"

echo "✅ Step 3 completed: Ruby extension built and installed"

# Step 4: Test and Verify
echo "🧪 Step 4: Testing FFE functionality..."
echo "🔍 Verifying functionality..."
bundle exec ruby -e "
require './lib/datadog/open_feature'
puts 'FFE supported: ' + Datadog::OpenFeature::Binding.supported?.to_s
puts 'Build successful!' if Datadog::OpenFeature::Binding.supported?
"

echo "🎯 Testing end-to-end functionality with NATIVE evaluator..."
bundle exec ruby -e "
require './lib/datadog/open_feature'

# Use Universal Flag Configuration JSON format
config_json = '{
  \"id\": \"1\",
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
}'

begin
  # Test Native Evaluator specifically
  puts '🔍 Testing Native FFE Evaluator...'
  native_evaluator = Datadog::OpenFeature::Binding::NativeEvaluator.new(config_json)
  context = Datadog::OpenFeature::Binding::EvaluationContext.new('test_user')
  
  puts 'Native evaluator supported: ' + Datadog::OpenFeature::Binding::NativeEvaluator.supported?.to_s
  puts 'Context in native mode: ' + context.native_mode?.to_s
  
  assignment = native_evaluator.get_assignment('test_flag', context)
  puts 'Assignment result: ' + assignment.inspect
  puts 'Assignment value: ' + assignment.value.inspect
  puts '🎉 Native FFE end-to-end functionality verified!'
rescue => e
  puts 'Error: ' + e.message
  puts e.backtrace.first(5).join(\"\n\")
end
"

echo "📋 Running RSpec tests for native evaluator..."
bundle exec rspec spec/datadog/open_feature/binding/native_evaluator_spec.rb

echo "✅ Step 4 completed: FFE functionality verified"

echo "✅ All steps completed successfully!"
echo "🧹 Cleanup will be performed automatically..."
