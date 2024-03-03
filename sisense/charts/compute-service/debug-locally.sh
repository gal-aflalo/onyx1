#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o pipefail

output_file="$(date +"%s").yaml"

# Run helm to generate the output non-templated Kubernetes configuration YAML, all in output 1 YAML file.
helm template --debug -f ./ci/ci-values.yaml -f ./values.yaml mycomputeservice . > "$output_file"

# It's assumed you have Minikube running already. i.e. run this at some point earlier:
# minikube start

# Load that Kubernetes YAML into your local Minikube cluster
kubectl --context=minikube apply -f "$output_file"

# Now, you can see everything in Minikube and confirm it works
kubectl --context=minikube get -A all
