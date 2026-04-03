pipeline {
    agent { label 'docker' } 

    environment {
        APP_NAME = "work-app"
        NAMESPACE = "cicd-task"
        
        TARGET_RPS = "700"             
        SUCCESS_THRESHOLD = "95"        
        APP_API_TIMEOUT = "6000"        
        
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
    }

    stages {
        stage('Setup & Clean') {
            steps {
                // Подготовка 
                sh 'chmod +x gradlew scripts/*.sh'
                sh './gradlew clean'
            }
        }

        stage('Build Artifact') {
            steps {
                // JAR
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Сохраняем текущий образ 
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

        stage('Build Load to KIND') {
            steps {
                script {
                    // Сборка образа с уникальным тегом с номером билда 
                    def imageTag = "${env.APP_NAME}:build-${env.BUILD_NUMBER}"
                    sh "docker build -t ${imageTag} ."
                    // загрузка образа в локальный кластер 
                    sh "kind load docker-image ${imageTag} --name kind"
                    env.FINAL_IMAGE = imageTag
                }
            }
        }

        stage('Deploy & Configure K8s') {
            steps {
                script {
                    //очистка олд ингрес ресурсов для предотвращения конфликта
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
                    // Обновление образа в деплое и ожидание завершения 
                    sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n ${env.NAMESPACE}"
                    sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE} --timeout=180s"
                }
            }
        }

        stage('Wait & Settle') {
            steps {
                script {
                    echo "Waiting for stable 200 OK from the service..."
                    //проверка доступности сервиса перед началом тестов
                    sh """
                        for i in {1..20}; do
                          CODE=\$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 ${env.LOAD_TEST_URL} || echo "000")
                          if [ "\$CODE" == "200" ]; then
                            echo "Service is UP. Waiting 15s for network convergence..."
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
                    sh "go version || echo 'Go not found'"
                    
                    //передаем параметры из дженкинса в переменные среды скрипта
                    def testEnv = "LOAD_TEST_RPS=${env.TARGET_RPS} LOAD_TEST_TIMEOUT=${env.APP_API_TIMEOUT}ms"

                    echo "Starting Warm-up..."
                    sh "${testEnv} LOAD_TEST_RUN_NAME=warmup ./scripts/run-load-test.sh"
                    
                    echo "Starting Final Analysis..."
                    sh "${testEnv} LOAD_TEST_RUN_NAME=final ./scripts/run-load-test.sh"
                }
            }
        }

        stage('Quality Gate & Rollback') {
            steps {
                script {
                    // Чтение метрик
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
                    
                    echo "Final Analysis Results: Success RPS: ${rps}, Success Rate: ${rate}%"

                    //процент успеха и соответствие целевому RPS
                    if (rate < env.SUCCESS_THRESHOLD.toDouble() || rps < env.TARGET_RPS.toDouble()) {
                        echo "QUALITY GATE FAILED. Initiating automatic rollback to ${env.PREV_IMAGE}..."
                        if (env.PREV_IMAGE) {
                            sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n ${env.NAMESPACE}"
                            sh "kubectl rollout status deployment/${env.APP_NAME} -n ${env.NAMESPACE}"
                            error "Deployment rejected: performance did not meet the ${env.TARGET_RPS} RPS requirement."
                        } else {
                            error "Deployment rejected, but no previous image found for rollback."
                        }
                    } else {
                        echo "QUALITY GATE PASSED. New release is stable."
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
