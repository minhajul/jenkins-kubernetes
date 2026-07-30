# Jenkins image with Node.js + Docker CLI pre-installed
# Extends the official jenkins/jenkins:lts image
#
# Build:    docker build -f jenkins.Dockerfile -t jenkins-custom:lts .
# Push:     docker tag jenkins-custom:lts <your-registry>/jenkins-custom:lts
#           docker push <your-registry>/jenkins-custom:lts
#
# Then point k8s/jenkins/deployment.yaml at your image.

FROM jenkins/jenkins:lts

USER root

# Install Node.js 20 (matches app/Dockerfile so builds are consistent)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    # Pin npm to a version compatible with Node 20 (latest npm requires Node >=22)
    && npm install -g npm@10.8.2

# Install Docker CLI (so Jenkins can run `docker build` against host Docker)
# We use the static binary — no daemon, just the client.
ARG DOCKER_VERSION=27.3.1
RUN curl -fsSLo /tmp/docker.tgz \
      "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz \
    && chmod +x /usr/local/bin/docker

# Install kubectl (so the Jenkinsfile's Deploy stage can run `kubectl set image`)
ARG KUBECTL_VERSION=v1.30.0
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Verify installs
RUN node --version && npm --version && docker --version && kubectl version --client

USER jenkins