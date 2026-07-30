pipeline {
  agent any

  environment {
    APP_NAME       = 'nestjs-k8s-app'
    IMAGE_NAME     = "${APP_NAME}"
    BUILD_TAG      = "build-${BUILD_NUMBER}"
    K8S_NAMESPACE  = 'devops-tools'
    K8S_DEPLOYMENT = 'nestjs-app'
  }

  options {
    timestamps()
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds()
  }

  triggers {
    githubPush()
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Install') {
      steps {
        dir('app') {
          sh 'npm ci'
        }
      }
    }

    stage('Build (TypeScript)') {
      steps {
        dir('app') {
          sh 'npm run build'
        }
      }
    }

    stage('Test') {
      steps {
        dir('app') {
          sh 'npm test'
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        dir('app') {
          sh """
            docker build -t ${IMAGE_NAME}:${BUILD_TAG} .
            docker tag  ${IMAGE_NAME}:${BUILD_TAG} ${IMAGE_NAME}:latest
          """
        }
      }
    }

    stage('Deploy to K8s') {
      steps {
        sh """
          kubectl -n ${K8S_NAMESPACE} set image \
            deployment/${K8S_DEPLOYMENT} \
            ${K8S_DEPLOYMENT}=${IMAGE_NAME}:${BUILD_TAG} \
            --record
          kubectl -n ${K8S_NAMESPACE} rollout status deployment/${K8S_DEPLOYMENT}
        """
      }
    }
  }

  post {
    success {
      echo "Deployed ${IMAGE_NAME}:${BUILD_TAG} to ${K8S_NAMESPACE}/${K8S_DEPLOYMENT}"
    }
    failure {
      echo 'Build failed. See console output above.'
    }
    always {
      sh 'docker rmi ${IMAGE_NAME}:${BUILD_TAG} || true'
    }
  }
}
