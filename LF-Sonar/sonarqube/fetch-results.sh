#!/bin/bash

TOKEN=$1
PROJECT_KEY="multi-module-project"
SONAR_URL="http://localhost:9000"

echo "📡 Fetching metrics..."
curl -s -u squ_051ae3b0c1467da95c8fa04c086ebb450a3d6faf: --get "https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud/api/measures/component?component=multi-module-issues&metricKeys=ncloc" | jq
curl -u admin:"Tn%G;fqj?C&__" -s https://gepardec-sonarqube.apps.cloudscale-lpg-2.appuio.cloud/api/measures/component?component=multi-module-issues%26metricKeys=ncloc | jq