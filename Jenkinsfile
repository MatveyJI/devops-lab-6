pipeline {
    agent { label 'docker' }

    environment {
        EXTERNAL_REGISTRY = "host.docker.internal:5000"
        INTERNAL_REGISTRY = "registry.cicd-task.svc.cluster.local:443"
        APP_NAME = "work-app"
        
        // Параметры для нагрузочного теста (пригодятся в следующих стадиях)
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
            }
        }

        stage('Capture Previous Release') {
            steps {
                script {
                    // Получаем текущий образ, чтобы знать куда откатываться
                    def currentImage = sh(
                        returnStatus: true, 
                        script: "kubectl get deployment/${env.APP_NAME} -n cicd-task"
                    ) == 0 ? sh(
                        script: "kubectl get deployment/${env.APP_NAME} -n cicd-task -o jsonpath='{.spec.template.spec.containers[0].image}'",
                        returnStdout: true
                    ).trim() : ""

                    if (currentImage && currentImage != "null") {
                        env.PREV_IMAGE = currentImage
                    } else {
                        env.PREV_IMAGE = "${env.INTERNAL_REGISTRY}/${env.APP_NAME}:latest"
                    }
                    echo "PREV_IMAGE set to: ${env.PREV_IMAGE}"
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                script {
                    env.BUILD_TAG = "${env.EXTERNAL_REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    env.K8S_TAG = "${env.INTERNAL_REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    
                    echo "Step 1: Building Docker image..."
                    sh "docker build -t ${env.BUILD_TAG} ."
                    
                    echo "Step 2: Pushing to registry..."
                    // Используем ID 'registry-creds', который ты создал в Jenkins
                    withCredentials([usernamePassword(credentialsId: 'registry-creds', 
                                     passwordVariable: 'REG_PASS', 
                                     usernameVariable: 'REG_USER')]) {
                        
                        sh "docker login ${env.EXTERNAL_REGISTRY} -u ${REG_USER} -p ${REG_PASS}"
                        sh "docker push ${env.BUILD_TAG}"
                        // Очищаем за собой данные логина
                        sh "docker logout ${env.EXTERNAL_REGISTRY}"
                    }
                    
                    echo "Step 3: Creating internal tag for K8s..."
                    sh "docker tag ${env.BUILD_TAG} ${env.K8S_TAG}"
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                echo "Deploying image: ${env.K8S_TAG}"
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.K8S_TAG} -n cicd-task"
                sh "kubectl rollout status deployment/${env.APP_NAME} -n cicd-task --timeout=180s"
            }
        }
    }

    post {
        failure {
            script {
                if (env.PREV_IMAGE) {
                    echo "Rollback initiated to: ${env.PREV_IMAGE}"
                    sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.PREV_IMAGE} -n cicd-task"
                }
            }
        }
        always {
            // Сохраняем отчеты, если они были созданы в папке artifacts
            archiveArtifacts artifacts: 'build/reports/**', allowEmptyArchive: true
        }
    }
}
