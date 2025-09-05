pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'RUN_STAGE01_INIT',  defaultValue: false, description: 'Create/refresh namespace and Docker Hub secret')
    booleanParam(name: 'BUILD_FETCHER',     defaultValue: true,  description: 'Build & push docker.io/meir25/stockops-fetcher:latest via Kaniko in k3s')
    booleanParam(name: 'BUILD_NEWS',        defaultValue: true,  description: 'Build & push docker.io/meir25/stockops-news:latest via Kaniko in k3s')
    booleanParam(name: 'DEPLOY_APPS',       defaultValue: true,  description: 'Apply k8s deployments/services for fetcher & news (+ Grafana & InfluxDB)')
  }

  environment {
    // Paths inside this repo
    STAGE01 = 'stages/01-namespace-and-registry-secret'
    STAGE02_FETCHER = 'stages/02-kaniko-build'
    STAGE02_NEWS    = 'stages/02b-kaniko-build-news'
    STAGE03 = 'stages/03-k8s-deploy'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          chmod +x $STAGE01/*.sh || true
          chmod +x $STAGE02_FETCHER/*.sh || true
          chmod +x $STAGE02_NEWS/*.sh || true
          chmod +x $STAGE03/*.sh || true
        '''
      }
    }

    stage('Stage 01: init (namespace + registry secret)') {
      when { expression { return params.RUN_STAGE01_INIT } }
      steps {
        withCredentials([file(credentialsId: 'k3s-token', variable: 'KCFG')]) {
          sh """
            set -eux
            # Ensure KUBECONFIG path for our scripts
            sed -i 's#^KUBECONFIG_FILE=.*#KUBECONFIG_FILE=${KCFG}#' $STAGE01/.env
            $STAGE01/apply.sh
            $STAGE01/verify.sh
          """
        }
      }
    }

    stage('Stage 02A: Kaniko build — fetcher') {
      when { expression { return params.BUILD_FETCHER } }
      steps {
        withCredentials([file(credentialsId: 'k3s-token', variable: 'KCFG')]) {
          sh """
            set -eux
            sed -i 's#^KUBECONFIG_FILE=.*#KUBECONFIG_FILE=${KCFG}#' $STAGE02_FETCHER/.env
            $STAGE02_FETCHER/cleanup.sh || true
            $STAGE02_FETCHER/apply.sh
            # Stream until completion
            $STAGE02_FETCHER/logs.sh
            # Final status (json) - jq optional, so just print
            $STAGE02_FETCHER/status.sh || true
          """
        }
      }
    }

    stage('Stage 02B: Kaniko build — news') {
      when { expression { return params.BUILD_NEWS } }
      steps {
        withCredentials([file(credentialsId: 'k3s-token', variable: 'KCFG')]) {
          sh """
            set -eux
            sed -i 's#^KUBECONFIG_FILE=.*#KUBECONFIG_FILE=${KCFG}#' $STAGE02_NEWS/.env
            $STAGE02_NEWS/cleanup.sh || true
            $STAGE02_NEWS/apply.sh
            # Stream until completion
            $STAGE02_NEWS/logs.sh
            # Final status
            $STAGE02_NEWS/status.sh || true
          """
        }
      }
    }

    stage('Stage 03: Deploy to k3s') {
      when { expression { return params.DEPLOY_APPS } }
      steps {
        withCredentials([file(credentialsId: 'k3s-token', variable: 'KCFG')]) {
          sh """
            set -eux
            sed -i 's#^KUBECONFIG_FILE=.*#KUBECONFIG_FILE=${KCFG}#' $STAGE03/.env
            $STAGE03/apply.sh
            $STAGE03/verify.sh
          """
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/logs/*.log', allowEmptyArchive: true
    }
  }
}

