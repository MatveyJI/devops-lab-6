pipeline {
    agent any

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
                    env.PREV_IMAGE = sh(
                        returnStdout: true,
                        script: "kubectl get deployment/${APP_NAME} -o jsonpath=\"{.spec.template.spec.containers[?(@.name=='${APP_NAME}')].image}\""
                    ).trim()

                    if (!env.PREV_IMAGE) {
                        error('Не удалось определить предыдущий image для rollback')
                    }

                    echo "Captured previous image tag for rollback"
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    def imageTag = "${env.BUILD_NUMBER}"
                    env.NEW_IMAGE = "${REGISTRY}/${APP_NAME}:${imageTag}"

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
                sh "kubectl wait --for=condition=ready pod -l app=${APP_NAME} --timeout=180s"
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

                    if (!successRateRaw || !successRpsRaw) {
                        error('Не удалось извлечь метрики из второго прогона нагрузочного теста')
                    }

                    BigDecimal successRate = new BigDecimal(successRateRaw)
                    BigDecimal successRps = new BigDecimal(successRpsRaw)
                    BigDecimal targetRps = new BigDecimal(env.TARGET_RPS)
                    BigDecimal successThreshold = new BigDecimal(env.SUCCESS_THRESHOLD)

                    echo "Run #2 metrics: successRate=${successRate}%, successRPS=${successRps}, targetRPS=${targetRps}"

                    if (successRate < successThreshold) {
                        error("Провал качества релиза: successRate ${successRate}% < ${successThreshold}%")
                    }

                    if (successRps < targetRps) {
                        error("Провал производительности: successRPS ${successRps} < targetRPS ${targetRps}")
                    }

                    env.RELEASE_APPROVED = 'true'
                }
            }
        }
    }

    post {
        failure {
            script {
                if (env.PREV_IMAGE?.trim()) {
                    echo 'Release failed. Rolling back to previous stable image.'
                    sh "kubectl set image deployment/${APP_NAME} ${APP_NAME}=${env.PREV_IMAGE}"
                    sh "kubectl rollout status deployment/${APP_NAME} --timeout=180s"
                    sh "kubectl wait --for=condition=ready pod -l app=${APP_NAME} --timeout=180s"
                    sh "curl -fsS http://work.127.0.0.1.nip.io/work/status >/dev/null"
                }
            }
        }

        success {
            script {
                if (env.RELEASE_APPROVED == 'true') {
                    echo "Release approved and kept: ${env.NEW_IMAGE}"
                }
            }
        }

        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/**', allowEmptyArchive: true, fingerprint: true
        }
    }
}
