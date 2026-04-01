pipeline {
    agent { label 'docker' }

    environment {
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        // Параметры качества из задания
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
                // Сборка fast-jar для работы внутри контейнера
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Фиксируем текущий образ для возможности отката
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
                    // Генерация уникального тега (запрет на latest)
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
                
                // Настройка политики для локальных образов
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
                    echo "Waiting for endpoint to be ready..."
                    // Цикл проверки доступности (до 10 попыток), чтобы избежать Connection Reset
                    sh """
                        for i in {1..10}; do 
                          curl -s -o /dev/null -w '%{http_code}' ${env.LOAD_TEST_URL} | grep 200 && break || sleep 5; 
                        done
                    """
                }
            }
        }

        stage('Load Testing') {
            steps {
                script {
                    // Выполнение двух прогонов согласно требованиям
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
                    // Чтение результатов из созданного скриптом файла метрик
                    def metricsFile = "artifacts/load-tests/final.metrics"
                    if (!fileExists(metricsFile)) {
                        error "Metrics file not found. Load test might have failed."
                    }
                    
                    def props = readProperties file: metricsFile
                    double actualRps = props['SUCCESS_RPS'] ? props['SUCCESS_RPS'].toDouble() : 0
                    double successRate = props['SUCCESS_RATE'] ? props['SUCCESS_RATE'].toDouble() : 0
                    
                    double targetRps = env.TARGET_RPS.toDouble()
                    double threshold = env.SUCCESS_THRESHOLD.toDouble()

                    echo "Final Metrics -> RPS: ${actualRps}, Success Rate: ${successRate}%"

                    if (successRate < threshold || actualRps < targetRps) {
                        echo "Quality Gate FAILED (Target RPS: ${targetRps}, Success: ${threshold}%). Initiating Rollback..."
                        if (env.PREV_IMAGE && env.PREV_IMAGE != "") {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                            error "Release rejected and rolled back to ${env.PREV_IMAGE}"
                        } else {
                            error "Release rejected, but no previous version found for rollback."
                        }
                    } else {
                        echo "Quality Gate PASSED. Deployment confirmed."
                    }
                }
            }
        }
    }

    post {
        always {
            // Сохранение логов и отчетов в артефакты Jenkins
            archiveArtifacts artifacts: 'artifacts/load-tests/*.log, artifacts/load-tests/*.metrics', allowEmptyArchive: true
            archiveArtifacts artifacts: 'build/reports/**', allowEmptyArchive: true
        }
    }
}
