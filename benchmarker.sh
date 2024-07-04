#!/bin/bash

# Ensure environment variables are set
if [ -z "$THRESHOLD" ] || [ -z "$CONFIG_FILE" ]; then
  echo "Environment variables THRESHOLD and CONFIG_FILE must be set."
  exit 1
fi

SHOW_FULL_RESULT=${SHOW_FULL_RESULT:-false}

# Install yq if not installed
if ! command -v yq &> /dev/null
then
    echo "yq could not be found, installing..."
    sudo apt-get update
    sudo apt-get install -y wget
    wget https://github.com/mikefarah/yq/releases/download/v4.18.1/yq_linux_amd64 -O /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
fi

# Install jq if not installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, installing..."
    sudo apt-get update
    sudo apt-get install -y jq
fi

# Parse the YAML file to extract endpoints
ENDPOINTS=$(yq eval '.endpoints' -o=json $CONFIG_FILE)

# Check if endpoints is empty
if [ -z "$ENDPOINTS" ]; then
  echo "No endpoints found in the configuration file."
  exit 1
fi

# Write parsed endpoints to a temporary file
echo "$ENDPOINTS" | jq -c '.[]' > endpoints.tmp

# Preliminary configuration check
PRELIM_CHECK_FAILED=false
while read -r ENDPOINT; do
  URL=$(echo "$ENDPOINT" | jq -r '.url')
  METHOD=$(echo "$ENDPOINT" | jq -r '.method')
  PAYLOAD=$(echo "$ENDPOINT" | jq -r '.payload // empty')

  if [ -z "$URL" ] || [ -z "$METHOD" ]; then
    echo "❌ Invalid endpoint data: $ENDPOINT"
    PRELIM_CHECK_FAILED=true
  fi

  if [[ "$METHOD" == "POST" || "$METHOD" == "PUT" || "$METHOD" == "PATCH" || "$METHOD" == "DELETE" ]]; then
    if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" == "empty" ]; then
      echo "❌ Error: Payload must be provided for $METHOD $URL"
      PRELIM_CHECK_FAILED=true
    fi
  fi
done < endpoints.tmp

# If the preliminary check fails, exit
if [ "$PRELIM_CHECK_FAILED" = true ]; then
  echo "⚙️ Invalid endpoint configuration file. Aborting test."
  rm endpoints.tmp
  exit 1
fi

FAILED_TEST=false

# Loop through each endpoint and perform benchmarking
while read -r ENDPOINT; do
  URL=$(echo "$ENDPOINT" | jq -r '.url')
  METHOD=$(echo "$ENDPOINT" | jq -r '.method')
  PAYLOAD=$(echo "$ENDPOINT" | jq -r '.payload // empty')

  echo "👾 Testing $METHOD $URL with payload: $PAYLOAD"
  
  # Unfortunately, ApacheBench does not natively support PUT, PATCH, or DELETE methods.
  # This is just for the sake of the testing. In order to support other than GET/PUT/POST, we should change ApacheBench for something else.
  if [[ "$METHOD" == "POST" || "$METHOD" == "PUT" || "$METHOD" == "PATCH" || "$METHOD" == "DELETE" ]]; then
    # Run Apache Benchmark for PUT, PATCH, POST, DELETE request
    RESULT=$(ab -n 100 -c 10 -p <(echo "$PAYLOAD") -T 'application/json' "$URL" 2>&1)
  else
    # Run Apache Benchmark for GET/OPTIONS request
    RESULT=$(ab -n 100 -c 10 "$URL" 2>&1)
  fi

  # Filter out the unwanted lines from the output
  CLEAN_RESULT=$(echo "$RESULT" | sed '/This is ApacheBench, Version/d' | sed '/Copyright/d' | sed '/Licensed to/d' | sed '/Benchmarking localhost/d')

  if [ "$SHOW_FULL_RESULT" == "true" ]; then
    echo "Benchmark result for $METHOD $URL:"
    echo "$CLEAN_RESULT"
  fi

  # Extract the mean response time from the result
  MEAN_RESPONSE_TIME=$(echo "$CLEAN_RESULT" | grep "Time per request:" | grep "(mean)" | awk '{print $4}')
  
  echo "ℹ️ Mean response time: $MEAN_RESPONSE_TIME ms"

  # Convert to integer (milliseconds)
  MEAN_RESPONSE_TIME=${MEAN_RESPONSE_TIME%.*}

  # Check if MEAN_RESPONSE_TIME is empty
  if [ -z "$MEAN_RESPONSE_TIME" ]; then
    echo "Failed to extract mean response time for $URL"
    FAILED_TEST=true
    continue
  fi

  # Compare with threshold
  if [ "$MEAN_RESPONSE_TIME" -gt "$THRESHOLD" ]; then
    echo "❌ Performance test failed: Mean response time ($MEAN_RESPONSE_TIME ms) exceeds threshold ($THRESHOLD ms)"
    FAILED_TEST=true
  else
    echo "✅ Performance test passed: Mean response time ($MEAN_RESPONSE_TIME ms) is within threshold ($THRESHOLD ms)"
  fi
done < endpoints.tmp

rm endpoints.tmp

# Exit with failure if any test failed
if $FAILED_TEST; then
  echo "❌ Performance test failed"
  exit 1
else
  echo "✅ Performance test passed"
  exit 0
fi