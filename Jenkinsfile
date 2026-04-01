pipeline {
    agent { label 'docker' }

    environment {
        REGISTRY = "registry.cicd-task.svc.cluster.local:443"
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
                // Проверка для отладки: посмотрим, что реально лежит в build
                sh 'ls -R build/' 
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    def currentImage = sh(
                        returnStdout: true,
                        script: "kubectl get deployment/${env.APP_NAME} -o jsonpath='{.spec.template.spec.containers[0].image}' || echo ''"
                    ).trim()

                    if (currentImage && currentImage != "" && currentImage != "null") {
                        env.PREV_IMAGE = currentImage
                    } else {
                        env.PREV_IMAGE = "${env.REGISTRY}/${env.APP_NAME}:latest"
                    }
                    echo "PREV_IMAGE set to: ${env.PREV_IMAGE}"
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    env.NEW_IMAGE = "${env.REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    echo "Building: ${env.NEW_IMAGE}"
                    sh "docker build -t ${env.NEW_IMAGE} ."
                    sh "docker push ${env.NEW_IMAGE}"
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.NEW_IMAGE}"
                sh "kubectl rollout status deployment/${env.APP_NAME} --timeout=180s"
            }
        }

        // ... остальные стадии (тесты и анализ) оставить как были
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
