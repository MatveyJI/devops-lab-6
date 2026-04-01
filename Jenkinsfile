pipeline {
    agent { label 'docker' }

    environment {
        REGISTRY = "registry.cicd-task.svc.cluster.local:443"
        APP_NAME = "work-app"
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
        TARGET_RPS = "220"
        LOAD_TEST_DURATION = "90s"
        LOAD_TEST_INTERVAL = "1s"
        LOAD_TEST_TIMEOUT = "30s"
        SUCCESS_THRESHOLD = "95"
        PREV_IMAGE = ""
        NEW_IMAGE = ""
        RELEASE_APPROVED = "false"
    }

    stages {
        stage('Setup & Clean') {
            steps {
                sh 'chmod +x gradlew scripts/run-load-test.sh'
                sh './gradlew clean'
            }
        }

        stage('Build Artifact') {
            steps {
                sh './gradlew build -x test'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Используем try-catch или проверку вывода, чтобы избежать падения
                    def rawOutput = sh(
                        returnStdout: true,
                        script: "kubectl get deployment/${APP_NAME} -o jsonpath='{.spec.template.spec.containers[0].image}' || echo 'none'"
                    ).trim()

                    if (rawOutput && rawOutput != "none" && rawOutput != "null" && rawOutput != "") {
                        env.PREV_IMAGE = rawOutput
                        echo "Captured previous image: ${env.PREV_IMAGE}"
                    } else {
                        // Если деплоймент новый, откатываться будем на дефолтный тег
                        env.PREV_IMAGE = "${REGISTRY}/${APP_NAME}:latest"
                        echo "No valid previous image found in K8s. Fallback set to: ${env.PREV_IMAGE}"
                    }
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}"
                    env.NEW_IMAGE = "${REGISTRY}/${APP_NAME}:${imageTag}"
                    
                    echo "Starting Docker build for image: ${env.NEW_IMAGE}"
                    sh "docker build -t ${env.NEW_IMAGE} ."
                    sh "docker push ${env.NEW_IMAGE}"
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                sh "kubectl set image deployment/${APP_NAME} ${APP_NAME}=${env.NEW_IMAGE}"
            }
        }

        stage('Verify Rollout') {
            steps {
                sh "kubectl rollout status deployment/${APP_NAME} --timeout=180s"
            }
        }

        stage('Load Test Run #1 (Warmup)') {
            steps {
                sh '''
                    mkdir -p artifacts/load-tests
                    LOAD_TEST_OUTPUT_DIR="artifacts/load-tests" \
                    LOAD_TEST_RUN_NAME="run1" \
                    LOAD_TEST_URL="${LOAD_TEST_URL}" \
                    LOAD_TEST_RPS="${TARGET_RPS}" \
                    LOAD_TEST_DURATION="${LOAD_TEST_DURATION}" \
                    LOAD_TEST_INTERVAL="${LOAD_TEST_INTERVAL}" \
                    LOAD_TEST_TIMEOUT="${LOAD_TEST_TIMEOUT}" \
                    LOAD_TEST_ALLOW_AB_FALLBACK="false" \
                    ./scripts/run-load-test.sh
                '''
            }
        }

        stage('Load Test Run #2 (Gate)') {
            steps {
                sh '''
                    mkdir -p artifacts/load-tests
                    LOAD_TEST_OUTPUT_DIR="artifacts/load-tests" \
                    LOAD_TEST_RUN_NAME="run2" \
                    LOAD_TEST_URL="${LOAD_TEST_URL}" \
                    LOAD_TEST_RPS="${TARGET_RPS}" \
                    LOAD_TEST_DURATION="${LOAD_TEST_DURATION}" \
                    LOAD_TEST_INTERVAL="${LOAD_TEST_INTERVAL}" \
                    LOAD_TEST_TIMEOUT="${LOAD_TEST_TIMEOUT}" \
                    LOAD_TEST_ALLOW_AB_FALLBACK="false" \
                    ./scripts/run-load-test.sh
                '''
            }
        }

        stage('Analyze Run #2') {
            steps {
                script {
                    def metricsPath = 'artifacts/load-tests/run2.metrics'
                    def successRateRaw = sh(returnStdout: true, script: "grep '^SUCCESS_RATE=' ${metricsPath} | cut -d= -f2").trim()
                    def successRpsRaw = sh(returnStdout: true, script: "grep '^SUCCESS_RPS=' ${metricsPath} | cut -d= -f2").trim()

                    BigDecimal successRate = new BigDecimal(successRateRaw)
                    BigDecimal successRps = new BigDecimal(successRpsRaw)
                    
                    echo "Results: Rate ${successRate}%, RPS ${successRps}"

                    if (successRate < new BigDecimal(env.SUCCESS_THRESHOLD) || successRps < new BigDecimal(env.TARGET_RPS)) {
                        error("Performance criteria not met!")
                    }
                    env.RELEASE_APPROVED = 'true'
                }
            }
        }
    }

    post {
        failure {
            script {
                if (env.PREV_IMAGE) {
                    echo "ROLLBACK to ${env.PREV_IMAGE}"
                    sh "kubectl set image deployment/${APP_NAME} ${APP_NAME}=${env.PREV_IMAGE}"
                }
            }
        }
        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/**', allowEmptyArchive: true
        }
    }
}
