pipeline {
    agent { label 'docker' }

    environment {
        // Используем приватный registry внутри кластера
        INTERNAL_REGISTRY = "registry.cicd-task.svc.cluster.local:443"
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        
        // Параметры нагрузочного тестирования
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
        TARGET_RPS = "220"
        LOAD_TEST_DURATION = "90s"
        LOAD_TEST_INTERVAL = "1s"
        LOAD_TEST_TIMEOUT = "30s"
        SUCCESS_THRESHOLD = "95"
        
        // Переменные для хранения версий
        PREV_IMAGE = ""
        NEW_IMAGE = ""
        RELEASE_APPROVED = "false"
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
                // Используем fast-jar для Quarkus
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Захватываем текущий образ до обновления
                    env.PREV_IMAGE = sh(
                        returnStdout: true,
                        script: "kubectl get deployment/${APP_NAME} -n ${NAMESPACE} -o jsonpath=\"{.spec.template.spec.containers[?(@.name=='${APP_NAME}')].image}\""
                    ).trim()

                    if (!env.PREV_IMAGE) {
                        error('Не удалось определить предыдущий image для rollback')
                    }
                    
                    echo "Previous image: ${env.PREV_IMAGE}"
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    // Формируем уникальный тег (используем build number)
                    def buildTag = "build-${env.BUILD_NUMBER}"
                    env.NEW_IMAGE = "${env.INTERNAL_REGISTRY}/${env.APP_NAME}:${buildTag}"
                    
                    echo "Building image: ${env.NEW_IMAGE}"
                    sh "docker build -t ${env.NEW_IMAGE} ."
                    
                    echo "Pushing to registry: ${env.INTERNAL_REGISTRY}"
                    sh "docker push ${env.NEW_IMAGE}"
                    
                    // Загружаем образ в KIND для локального использования
                    sh "kind load docker-image ${env.NEW_IMAGE} --name kind"
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                echo "Deploying new version: ${env.NEW_IMAGE}"
                
                // Обновляем образ в deployment
                sh "kubectl set image deployment/${APP_NAME} ${APP_NAME}=${env.NEW_IMAGE} -n ${NAMESPACE}"
                
                // Устанавливаем политику IfNotPresent для локальных образов
                sh """
                    kubectl patch deployment ${APP_NAME} -n ${NAMESPACE} \
                    -p '{"spec":{"template":{"spec":{"containers":[{"name":"${APP_NAME}","imagePullPolicy":"IfNotPresent"}]}}}}'
                """
            }
        }

        stage('Verify Rollout') {
            steps {
                // Ожидаем успешного обновления
                sh "kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=180s"
                sh "kubectl wait --for=condition=ready pod -l app=${APP_NAME} -n ${NAMESPACE} --timeout=180s"
                
                // Проверяем доступность приложения
                sh "curl -fsS http://work.127.0.0.1.nip.io/work/status >/dev/null"
            }
        }

        stage('Load Test #1 (Warmup)') {
            steps {
                script {
                    // Создаем директорию для артефактов
                    sh 'mkdir -p artifacts/load-tests'
                    
                    // Первый прогон для прогрева HPA
                    sh """
                        LOAD_TEST_OUTPUT_DIR="artifacts/load-tests" \
                        LOAD_TEST_RUN_NAME="run1_warmup" \
                        LOAD_TEST_URL="${LOAD_TEST_URL}" \
                        LOAD_TEST_RPS="${TARGET_RPS}" \
                        LOAD_TEST_DURATION="${LOAD_TEST_DURATION}" \
                        LOAD_TEST_INTERVAL="${LOAD_TEST_INTERVAL}" \
                        LOAD_TEST_TIMEOUT="${LOAD_TEST_TIMEOUT}" \
                        LOAD_TEST_ALLOW_AB_FALLBACK="false" \
                        ./scripts/run-load-test.sh
                    """
                    
                    echo "Warmup test completed. Waiting for HPA to stabilize..."
                    // Даем время HPA на масштабирование
                    sh 'sleep 30'
                }
            }
        }

        stage('Load Test #2 (Gate)') {
            steps {
                script {
                    // Второй прогон для принятия решения
                    sh """
                        LOAD_TEST_OUTPUT_DIR="artifacts/load-tests" \
                        LOAD_TEST_RUN_NAME="run2_gate" \
                        LOAD_TEST_URL="${LOAD_TEST_URL}" \
                        LOAD_TEST_RPS="${TARGET_RPS}" \
                        LOAD_TEST_DURATION="${LOAD_TEST_DURATION}" \
                        LOAD_TEST_INTERVAL="${LOAD_TEST_INTERVAL}" \
                        LOAD_TEST_TIMEOUT="${LOAD_TEST_TIMEOUT}" \
                        LOAD_TEST_ALLOW_AB_FALLBACK="false" \
                        ./scripts/run-load-test.sh
                    """
                }
            }
        }

        stage('Analyze Results') {
            steps {
                script {
                    def metricsPath = 'artifacts/load-tests/run2_gate.metrics'
                    
                    // Извлекаем метрики из файла
                    def successRateRaw = sh(
                        returnStdout: true, 
                        script: "grep '^SUCCESS_RATE=' ${metricsPath} | cut -d= -f2 | tr -d '\\n\\r'"
                    ).trim()
                    
                    def successRpsRaw = sh(
                        returnStdout: true, 
                        script: "grep '^SUCCESS_RPS=' ${metricsPath} | cut -d= -f2 | tr -d '\\n\\r'"
                    ).trim()

                    if (!successRateRaw || !successRpsRaw) {
                        error('Не удалось извлечь метрики из второго прогона нагрузочного теста')
                    }

                    // Преобразуем строки в числа (заменяем запятую на точку если нужно)
                    successRateRaw = successRateRaw.replace(',', '.')
                    successRpsRaw = successRpsRaw.replace(',', '.')
                    
                    BigDecimal successRate = new BigDecimal(successRateRaw)
                    BigDecimal successRps = new BigDecimal(successRpsRaw)
                    BigDecimal targetRps = new BigDecimal(env.TARGET_RPS)
                    BigDecimal successThreshold = new BigDecimal(env.SUCCESS_THRESHOLD)

                    echo "========================================="
                    echo "Load Test Results (Run #2):"
                    echo "  Success Rate: ${successRate}%"
                    echo "  Successful RPS: ${successRps}"
                    echo "  Target RPS: ${targetRps}"
                    echo "  Threshold: ${successThreshold}%"
                    echo "========================================="

                    // Проверяем условия успешности релиза
                    if (successRate < successThreshold) {
                        error("Релиз не принят: процент успешных ответов ${successRate}% < ${successThreshold}%")
                    }

                    if (successRps < targetRps) {
                        error("Релиз не принят: успешный RPS ${successRps} < целевой RPS ${targetRps}")
                    }

                    env.RELEASE_APPROVED = 'true'
                    echo "✅ Релиз успешен! Новая версия принята."
                }
            }
        }
    }

    post {
        failure {
            script {
                echo "========================================="
                echo "❌ Релиз не прошел проверку!"
                echo "Инициируем откат на предыдущую версию..."
                echo "========================================="
                
                if (env.PREV_IMAGE?.trim()) {
                    try {
                        // Откатываем на предыдущий образ
                        sh "kubectl set image deployment/${APP_NAME} ${APP_NAME}=${env.PREV_IMAGE} -n ${NAMESPACE}"
                        
                        // Ожидаем завершения отката
                        sh "kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=180s"
                        sh "kubectl wait --for=condition=ready pod -l app=${APP_NAME} -n ${NAMESPACE} --timeout=180s"
                        
                        // Проверяем доступность после отката
                        sh "curl -fsS http://work.127.0.0.1.nip.io/work/status >/dev/null"
                        
                        echo "✅ Откат выполнен успешно. Текущая версия: ${env.PREV_IMAGE}"
                    } catch (Exception e) {
                        echo "⚠️ Ошибка при откате: ${e.getMessage()}"
                        currentBuild.result = 'UNSTABLE'
                    }
                } else {
                    echo "⚠️ Нет сохраненной предыдущей версии для отката!"
                }
            }
        }
        
        success {
            script {
                if (env.RELEASE_APPROVED == 'true') {
                    echo "========================================="
                    echo "✅ Релиз успешно завершен!"
                    echo "Новая версия: ${env.NEW_IMAGE}"
                    echo "========================================="
                }
            }
        }
        
        always {
            // Сохраняем результаты тестов как артефакты
            archiveArtifacts artifacts: 'artifacts/load-tests/**', 
                           allowEmptyArchive: true, 
                           fingerprint: true
                           
            // Сохраняем отчеты сборки
            archiveArtifacts artifacts: 'build/reports/**', 
                           allowEmptyArchive: true
                           
            echo "Pipeline execution completed. Status: ${currentBuild.currentResult}"
        }
    }
}