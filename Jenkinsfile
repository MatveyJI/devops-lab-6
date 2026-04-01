pipeline {
    agent { label 'docker' }

    environment {
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        TARGET_RPS = "220"
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
                    // Создаем/обновляем Service и Ingress, если их нет
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
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
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
                    
                    // Обновляем образ в Deployment
                    sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n ${env.NAMESPACE}"
                    
                    sh """
                        kubectl patch deployment ${env.APP_NAME} -n ${env.NAMESPACE} \
                        -p '{"spec":{"template":{"spec":{"containers":[{"name":"${env.APP_NAME}","imagePullPolicy":"IfNotPresent"}]}}}}'
                    """
                    
                    sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE} --timeout=180s"
                }
            }
        }

        stage('Wait for Availability') {
            steps {
                script {
                    echo "Waiting for ${env.LOAD_TEST_URL} to be 200 OK..."
                    sh """
                        SUCCESS=0
                        for i in {1..20}; do
                          CODE=\$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 ${env.LOAD_TEST_URL} || echo "000")
                          if [ "\$CODE" == "200" ]; then
                            echo "Ready!"
                            SUCCESS=1
                            break
                          fi
                          echo "Attempt \$i: HTTP \$CODE. Retrying..."
                          sleep 5
                        done
                        if [ "\$SUCCESS" == "0" ]; then exit 1; fi
                    """
                }
            }
        }

        stage('Load Testing') {
            steps {
                sh "LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh"
                sh "LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh"
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    def props = readProperties file: "artifacts/load-tests/final.metrics"
                    double rps = props['SUCCESS_RPS']?.toDouble() ?: 0
                    double rate = props['SUCCESS_RATE']?.toDouble() ?: 0
                    
                    if (rate < env.SUCCESS_THRESHOLD.toDouble() || rps < env.TARGET_RPS.toDouble()) {
                        if (env.PREV_IMAGE) {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            error "Rolled back to ${env.PREV_IMAGE}"
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/*, build/reports/**', allowEmptyArchive: true
        }
    }
}
