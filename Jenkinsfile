pipeline {
    agent { label 'docker' }

    environment {
        // Адрес для Docker (через ваш port-forward)
        EXTERNAL_REGISTRY = "host.docker.internal:5000"
        // Адрес для Kubernetes (внутри кластера)
        INTERNAL_REGISTRY = "registry.cicd-task.svc.cluster.local:443"
        
        APP_NAME = "work-app"
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
        TARGET_RPS = "220"
        SUCCESS_THRESHOLD = "95"
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
                sh 'ls -R build/' 
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Пытаемся получить текущий образ из деплоймента
                    def currentImage = sh(
                        returnStatus: false,
                        returnStdout: true,
                        script: "kubectl get deployment/${env.APP_NAME} -o jsonpath='{.spec.template.spec.containers[0].image}' || echo ''"
                    ).trim()

                    if (currentImage && currentImage != "" && currentImage != "null") {
                        env.PREV_IMAGE = currentImage
                    } else {
                        // Фолбек на внутренний адрес, если деплоймента еще нет
                        env.PREV_IMAGE = "${env.INTERNAL_REGISTRY}/${env.APP_NAME}:latest"
                    }
                    echo "PREV_IMAGE set to: ${env.PREV_IMAGE}"
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    // Для сборки и пуша используем localhost
                    env.BUILD_TAG = "${env.EXTERNAL_REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    // Для деплоя в K8s используем внутренний DNS
                    env.K8S_TAG = "${env.INTERNAL_REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    
                    echo "Building local tag: ${env.BUILD_TAG}"
                    sh "docker build -t ${env.BUILD_TAG} ."
                    
                    echo "Pushing to registry via port-forward..."
                    sh "docker push ${env.BUILD_TAG}"
                    
                    // Дополнительно тегируем внутренним именем, чтобы kubectl понимал, что деплоить
                    sh "docker tag ${env.BUILD_TAG} ${env.K8S_TAG}"
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                // Указываем K8s использовать ВНУТРЕННИЙ адрес для скачивания образа
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.K8S_TAG}"
                sh "kubectl rollout status deployment/${env.APP_NAME} --timeout=180s"
            }
        }
    }

    post {
        failure {
            script {
                if (env.PREV_IMAGE) {
                    echo "Rolling back to ${env.PREV_IMAGE}"
                    sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE}"
                }
            }
        }
        always {
            archiveArtifacts artifacts: 'artifacts/load-tests/**', allowEmptyArchive: true
        }
    }
}
