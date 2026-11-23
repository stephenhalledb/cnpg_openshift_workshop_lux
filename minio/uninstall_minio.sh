#!/bin/bash
. ../config.sh

${kubectl_cmd} delete namespace minio-system --ignore-not-found
