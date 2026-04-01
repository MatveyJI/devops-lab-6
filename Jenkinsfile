pipeline {
    agent { label 'docker' }

    environment {
        // Используем ClusterIP реестра, раз DNS (svc.cluster.local) капризничает
        INTERNAL_REGISTRY = "10.96.144.162:443"
        APP_NAME = "work-app"
        
        LOAD_TEST_URL = "http://work.127.0.0.1.nip.io/work"
        TARGET_RPS = "220"
        SUCCESS_THRESHOLD = "95"
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
                // Добавляем параметр для создания правильной структуры fast-jar
                sh './gradlew build -x test -Dquarkus.package.type=fast-jar'
            }
        }

        stage('Build & Load to KIND') {
            steps {
                script {
                    // Формируем тег
                    def imageTag = "${env.APP_NAME}:build-${env.BUILD_NUMBER}"
                    
                    echo "Building Docker image..."
                    sh "docker build -t ${imageTag} ."
                    
                    echo "Loading image directly to KIND (bypassing registry SSL issues)..."
                    // ВАЖНО: убедись, что на агенте есть команда kind и имя кластера совпадает
                    sh "kind load docker-image ${imageTag} --name kind"
                    
                    env.FINAL_IMAGE = imageTag
                }
            }
        }

        stage('Deploy to K8s') {
            steps {
                echo "Deploying image: ${env.FINAL_IMAGE}"
                // Устанавливаем образ
                sh "kubectl set image deployment/${env.APP_NAME} ${env.APP_NAME}=${env.FINAL_IMAGE} -n cicd-task"
                
                // ВАЖНО: устанавливаем политику IfNotPresent, чтобы K8s взял образ из ноды
                sh """
                    kubectl patch deployment ${env.APP_NAME} -n cicd-task \
                    -p '{"spec":{"template":{"spec":{"containers":[{"name":"${env.APP_NAME}","imagePullPolicy":"IfNotPresent"}]}}}}'
                """
                
                sh "kubectl rollout status deployment/${env.APP_NAME} -n cicd-task --timeout=180s"
            }
        }
    }

    post {
        failure {
            echo "Deployment failed. Check logs with: kubectl logs -l app=${env.APP_NAME} -n cicd-task"
        }
        always {
            archiveArtifacts artifacts: 'build/reports/**', allowEmptyArchive: true
        }
    }
}
