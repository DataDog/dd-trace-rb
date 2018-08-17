#!/bin/bash

STORAGE_DIR=$1
TEST_NAME=$2
TEST_FILE=benchmarks/$TEST_NAME.rb

RESULT_DIR=$STORAGE_DIR/$TEST_NAME
RESULT_FILE=$RESULT_DIR/benchmark-$CIRCLE_BUILD_NUM-$CIRCLE_NODE_INDEX.csv
mkdir -p $RESULT_DIR

bundle exec appraisal rails5-postgres-sidekiq ruby $TEST_FILE 2>&1 1>/dev/null | tee $RESULT_FILE