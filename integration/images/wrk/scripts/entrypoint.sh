#!/usr/bin/env bash
bash /vendor/dd-demo/http-health-check

# Start the load test
echo "== Starting load test... =="

if [[ $# -eq 0 ]] ; then
  echo "** No load test specified: pass wrk args as a command. **"
  echo "== Load test aborted. =="
  exit 1
else
  COMMAND="wrk $@"
  echo "Command: $COMMAND"
  /bin/bash -c "$COMMAND"
  echo "== Load test done. =="
  exit 0
fi
