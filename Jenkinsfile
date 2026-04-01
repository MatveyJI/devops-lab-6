pipeline {
    agent { label 'docker' }

    environment {
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        // Требования по нагрузке и качеству
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
                // Сборка fast-jar для корректной работы образа
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Сохраняем текущий образ для реализации отката [cite: 18]
                    def currentImage = sh(
                        returnStatus: true, 
                        script: "kubectl get deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                    ) == 0 ? sh(
                        script: "kubectl get deployment/${env.APP_NAME} -n ${env.NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}'",
                        returnStdout: true
                    ).trim() : ""

                    env.PREV_IMAGE = currentImage
                    echo "Previous image captured: ${env.PREV_IMAGE}"
                }
            }
        }

        stage('Build & Load to KIND') {
            steps {
                script {
                    // Использование уникальных тегов вместо latest [cite: 6]
                    def imageTag = "${env.APP_NAME}:build-${env.BUILD_NUMBER}"
                    
                    echo "Building Docker image..."
                    sh "docker build -t ${imageTag} ."
                    
                    echo "Loading image to KIND..."
                    sh "kind load docker-image ${imageTag} --name kind"
                    
                    env.FINAL_IMAGE = imageTag
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                echo "Deploying image: ${env.FINAL_IMAGE}"
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n ${env.NAMESPACE}"
                
                sh """
                    kubectl patch deployment ${env.APP_NAME} -n ${env.NAMESPACE} \
                    -p '{"spec":{"template":{"spec":{"containers":[{"name":"${env.APP_NAME}","imagePullPolicy":"IfNotPresent"}]}}}}'
                """
                
                // Ожидание завершения rollout [cite: 9]
                sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE} --timeout=180s"
            }
        }

        stage('Load Testing') {
            steps {
                script {
                    // Два прогона согласно заданию [cite: 12]
                    echo "Starting Load Test Run 1 (Warm-up)..."
                    sh "LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh"
                    
                    echo "Starting Load Test Run 2 (Analysis)..."
                    sh "LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh"
                }
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    // Анализ результатов второго прогона [cite: 14]
                    def metricsFile = "artifacts/load-tests/final.metrics"
                    def props = readProperties file: metricsFile
                    
                    double actualRps = props['SUCCESS_RPS'].toDouble()
                    double successRate = props['SUCCESS_RATE'].toDouble()
                    double targetRps = env.TARGET_RPS.toDouble()
                    double threshold = env.SUCCESS_THRESHOLD.toDouble()

                    echo "Analysis: RPS ${actualRps}/${targetRps}, Success Rate: ${successRate}%"

                    if (successRate < threshold || actualRps < targetRps) {
                        echo "Quality Gate FAILED. Initiating Rollback..."
                        if (env.PREV_IMAGE && env.PREV_IMAGE != "") {
                            // Откат на предыдущий стабильный тег [cite: 17, 18]
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                            error "Release rejected: metrics below threshold. Rolled back to ${env.PREV_IMAGE}"
                        } else {
                            error "Release rejected and no previous image found for rollback."
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
            // Сохранение результатов и отчетов [cite: 16]
            archiveArtifacts artifacts: 'artifacts/load-tests/*.log, artifacts/load-tests/*.metrics', allowEmptyArchive: true
            archiveArtifacts artifacts: 'build/reports/**', allowEmptyArchive: true
        }
    }
}
