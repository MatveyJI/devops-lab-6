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

        stage('Deploy to K8s') {
            steps {
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n ${env.NAMESPACE}"
                sh """
                    kubectl patch deployment ${env.APP_NAME} -n ${env.NAMESPACE} \
                    -p '{"spec":{"template":{"spec":{"containers":[{"name":"${env.APP_NAME}","imagePullPolicy":"IfNotPresent"}]}}}}'
                """
                sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE} --timeout=180s"
            }
        }

        stage('Wait for Availability') {
            steps {
                script {
                    echo "Waiting for endpoint ${env.LOAD_TEST_URL} to return 200 OK..."
                    // Улучшенный цикл: если через 12 попыток (1 мин) нет 200 OK, пайплайн упадет
                    sh """
                        SUCCESS=0
                        for i in {1..12}; do
                          CODE=\$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --retry 0 ${env.LOAD_TEST_URL} || echo "000")
                          if [ "\$CODE" == "200" ]; then
                            echo "Endpoint is READY (HTTP 200)"
                            SUCCESS=1
                            break
                          fi
                          echo "Attempt \$i: Endpoint returned \$CODE. Retrying in 5s..."
                          sleep 5
                        done
                        if [ "\$SUCCESS" == "0" ]; then
                          echo "ERROR: Endpoint did not become ready in time"
                          exit 1
                        fi
                    """
                }
            }
        }

        stage('Load Testing') {
            steps {
                script {
                    echo "Starting Warm-up..."
                    sh "LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh"
                    sleep 5
                    echo "Starting Final Analysis..."
                    sh "LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh"
                }
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    def metricsFile = "artifacts/load-tests/final.metrics"
                    if (!fileExists(metricsFile)) {
                        error "Metrics file not found!"
                    }
                    
                    def props = readProperties file: metricsFile
                    double actualRps = props['SUCCESS_RPS'] ? props['SUCCESS_RPS'].toDouble() : 0
                    double successRate = props['SUCCESS_RATE'] ? props['SUCCESS_RATE'].toDouble() : 0
                    
                    if (successRate < env.SUCCESS_THRESHOLD.toDouble() || actualRps < env.TARGET_RPS.toDouble()) {
                        if (env.PREV_IMAGE) {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            error "Quality Gate failed. Rolled back to ${env.PREV_IMAGE}"
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/*.log, artifacts/load-tests/*.metrics, build/reports/**', allowEmptyArchive: true
        }
    }
}
