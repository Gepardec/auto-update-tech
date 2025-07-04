#!/bin/bash

cd my-java-project

echo "🧪 Running SonarQube analysis..."
mvn clean verify sonar:sonar \
  -Dsonar.projectKey=java-demo \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.login="$TOKEN"
