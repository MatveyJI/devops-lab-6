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
                    echo "Captured PREV_IMAGE: ${env.PREV_IMAGE}"
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
                    echo "Waiting for ${env.LOAD_TEST_URL}..."
                    // Увеличено до 24 попыток (2 минуты) + вывод логов при ошибке
                    sh """
                        SUCCESS=0
                        for i in {1..24}; do
                          CODE=\$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 ${env.LOAD_TEST_URL} || echo "000")
                          if [ "\$CODE" == "200" ]; then
                            echo "SUCCESS: Endpoint is up!"
                            SUCCESS=1
                            break
                          fi
                          echo "Attempt \$i: HTTP \$CODE. Waiting 5s..."
                          sleep 5
                        done
                        if [ "\$SUCCESS" == "0" ]; then
                          echo "--- DEBUG INFO ---"
                          kubectl get pods -n ${env.NAMESPACE}
                          kubectl describe deployment ${env.APP_NAME} -n ${env.NAMESPACE}
                          exit 1
                        fi
                    """
                }
            }
        }

        stage('Load Testing') {
            steps {
                script {
                    echo "Running Warm-up..."
                    sh "LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh"
                    echo "Running Final Test..."
                    sh "LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh"
                }
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    def props = readProperties file: "artifacts/load-tests/final.metrics"
                    double actualRps = props['SUCCESS_RPS']?.toDouble() ?: 0
                    double successRate = props['SUCCESS_RATE']?.toDouble() ?: 0
                    
                    if (successRate < env.SUCCESS_THRESHOLD.toDouble() || actualRps < env.TARGET_RPS.toDouble()) {
                        echo "QUALITY GATE FAILED: RPS \$actualRps, Success \$successRate%"
                        if (env.PREV_IMAGE && env.PREV_IMAGE != "") {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                            error "Rollback executed to \${env.PREV_IMAGE}"
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
