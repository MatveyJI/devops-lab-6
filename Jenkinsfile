pipeline {
    agent { label 'docker' }

    environment {
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        TARGET_RPS = "30" 
        SUCCESS_THRESHOLD = "95"
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
    }

    stages {
        stage('Setup & Clean') {
            steps {
                sh 'chmod +x gradlew scripts/*.sh'
                sh './gradlew clean'
            }
        }

        stage('Build Artifact') {
            steps {
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    def currentImage = sh(
                        returnStatus: true, 
                        script: "kubectl get deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                    ) == 0 ? sh(
                        script: "kubectl get deployment/${env.APP_NAME} -n ${env.NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}'",
                        returnStdout: true
                    ).trim() : ""
                    env.PREV_IMAGE = currentImage
                }
            }
        }

        stage('Build & Load to KIND') {
            steps {
                script {
                    def imageTag = "${env.APP_NAME}:build-${env.BUILD_NUMBER}"
                    sh "docker build -t ${imageTag} ."
                    sh "kind load docker-image ${imageTag} --name kind"
                    env.FINAL_IMAGE = imageTag
                }
            }
        }

        stage('Deploy & Configure K8s') {
            steps {
                script {
                    sh "kubectl delete ingress work-app-ingress -n default --ignore-not-found"
                    sh "kubectl delete ingress ${env.APP_NAME} -n ${env.NAMESPACE} --ignore-not-found"

                    sh """
cat <<EOF | kubectl apply -n ${env.NAMESPACE} -f -
apiVersion: v1
kind: Service
metadata:
  name: ${env.APP_NAME}
spec:
  selector:
    app: ${env.APP_NAME}
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${env.APP_NAME}
spec:
  ingressClassName: nginx
  rules:
  - host: work.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${env.APP_NAME}
            port:
              number: 80
EOF
                    """
                    sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n ${env.NAMESPACE}"
                    sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE} --timeout=180s"
                }
            }
        }

        stage('Wait & Settle') {
            steps {
                script {
                    echo "Waiting for stable 200 OK..."
                    sh """
                        for i in {1..20}; do
                          CODE=\$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 ${env.LOAD_TEST_URL} || echo "000")
                          if [ "\$CODE" == "200" ]; then
                            echo "Service is up. Waiting 15s for networking to settle..."
                            sleep 15
                            exit 0
                          fi
                          sleep 5
                        done
                        exit 1
                    """
                }
            }
        }

        stage('Load Testing') {
            steps {
                script {
                    // Проверяем наличие Go, но не падаем, если его нет
                    sh "go version || echo 'Go not found in system, scripts will use fallback'"
                    
                    echo "Starting Warm-up..."
                    sh """
                        for i in {1..3}; do
                          LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh && break || sleep 10
                        done
                    """
                    
                    echo "Starting Final Analysis..."
                    sh """
                        for i in {1..3}; do
                          LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh && break || sleep 10
                        done
                    """
                }
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    def propsFile = readFile("artifacts/load-tests/final.metrics")
                    def props = [:]
                    propsFile.eachLine { line ->
                        def parts = line.split('=')
                        if (parts.size() == 2) {
                            props[parts[0].trim()] = parts[1].trim()
                        }
                    }

                    double rps = props['SUCCESS_RPS']?.toDouble() ?: 0
                    double rate = props['SUCCESS_RATE']?.toDouble() ?: 0
                    
                    echo "Final Analysis: RPS ${rps} (Target: ${env.TARGET_RPS}), Success: ${rate}%"

                    if (rate < env.SUCCESS_THRESHOLD.toDouble() || rps < env.TARGET_RPS.toDouble()) {
                        echo "Quality Gate FAILED. Rolling back..."
                        if (env.PREV_IMAGE) {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                            error "Deployment rejected: performance too low."
                        }
                    } else {
                        echo "Quality Gate PASSED."
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/*', allowEmptyArchive: true
        }
    }
}
