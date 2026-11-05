
pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION = 'ap-south-1'
        DEPLOY_DIR = '/var/lib/jenkins/microdev-deploy'
    }

    stages {

        stage('Checkout Source') {
            steps {
                git branch: 'develop',
                    credentialsId: 'github-credentials',
                    url: 'https://github.com/prasadA7989/microservices-task.git'
            }
        }

        stage('Prepare Release') {
            steps {
                script {
                    def shortCommit = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${shortCommit}"
                }

                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    script {
                        env.AWS_ACCOUNT_ID = sh(
                            script: 'aws sts get-caller-identity --query Account --output text',
                            returnStdout: true
                        ).trim()
                    }
                }

                script {
                    env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                }

                echo "Release tag: ${env.IMAGE_TAG}"
            }
        }

        stage('Validate Configuration') {
            steps {
                sh '''
                    set -eu

                    terraform fmt -check -recursive terraform

                    terraform -chdir=terraform init -backend=false

                    terraform -chdir=terraform validate

                    export GRAFANA_ADMIN_PASSWORD=validation-only

                    docker compose -f deploy/compose.yaml config --quiet

                    echo "Configuration validation passed"
                '''
            }
        }

        stage('Build Docker Images') {
            steps {
                sh '''
                    set -eu

                    echo "Building User service"
                    docker build \
                      -t "$ECR_REGISTRY/microdev-user:$IMAGE_TAG" \
                      ./user-service

                    echo "Building Product service"
                    docker build \
                      -t "$ECR_REGISTRY/microdev-product:$IMAGE_TAG" \
                      ./product-service

                    echo "Building Order service"
                    docker build \
                      -t "$ECR_REGISTRY/microdev-order:$IMAGE_TAG" \
                      ./order-service

                    echo "All Docker images built successfully"
                '''
            }
        }

        stage('Run Application Tests') {
            steps {
                sh '''
                    set -eu

                    echo "Testing User service"
                    docker run --rm \
                      --entrypoint python \
                      "$ECR_REGISTRY/microdev-user:$IMAGE_TAG" \
                      -m unittest discover -s /app/tests -v

                    echo "Testing Product service"
                    docker run --rm \
                      --entrypoint python \
                      "$ECR_REGISTRY/microdev-product:$IMAGE_TAG" \
                      -m unittest discover -s /app/tests -v

                    echo "Testing Order service"
                    docker run --rm \
                      --entrypoint python \
                      "$ECR_REGISTRY/microdev-order:$IMAGE_TAG" \
                      -m unittest discover -s /app/tests -v

                    echo "All application tests passed"
                '''
            }
        }

        stage('Push Images to ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set +x
                        set -eu

                        aws ecr get-login-password \
                          --region "$AWS_REGION" |
                          docker login \
                            --username AWS \
                            --password-stdin "$ECR_REGISTRY"

                        docker push "$ECR_REGISTRY/microdev-user:$IMAGE_TAG"
                        docker push "$ECR_REGISTRY/microdev-product:$IMAGE_TAG"
                        docker push "$ECR_REGISTRY/microdev-order:$IMAGE_TAG"

                        docker logout "$ECR_REGISTRY"

                        echo "All images pushed to Amazon ECR"
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    ),
                    string(
                        credentialsId: 'grafana-admin-password',
                        variable: 'GRAFANA_ADMIN_PASSWORD'
                    )
                ]) {
                    sh '''
                        set +x
                        set -eu

                        echo "Preparing local deployment directory"

                        mkdir -p "$DEPLOY_DIR"
                        chmod 700 "$DEPLOY_DIR"

                        cp -a deploy/. "$DEPLOY_DIR/"

                        cd "$DEPLOY_DIR"

                        if [ -f .env ]; then
                            cp .env .env.previous
                        fi

                        umask 077

                        printf '%s\\n' \
                          "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID" \
                          "AWS_REGION=$AWS_REGION" \
                          "IMAGE_TAG=$IMAGE_TAG" > .env

                        echo "Authenticating Docker with ECR"

                        aws ecr get-login-password \
                          --region "$AWS_REGION" |
                          docker login \
                            --username AWS \
                            --password-stdin "$ECR_REGISTRY"

                        echo "Pulling Docker images"

                        docker compose -f compose.yaml pull

                        echo "Starting microservices and monitoring"

                        docker compose -f compose.yaml \
                          up -d --remove-orphans

                        echo "Deployment container status"

                        docker compose -f compose.yaml ps

                        docker logout "$ECR_REGISTRY"

                        echo "Local EC2 deployment completed"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -eu

                    echo "Waiting for microservice health checks"

                    for attempt in $(seq 1 20); do
                        if curl -fsS --max-time 5 \
                             http://127.0.0.1/users/health \
                             > /dev/null &&
                           curl -fsS --max-time 5 \
                             http://127.0.0.1/products/health \
                             > /dev/null &&
                           curl -fsS --max-time 5 \
                             http://127.0.0.1/orders/health \
                             > /dev/null
                        then
                            echo "All three microservices are healthy"
                            exit 0
                        fi

                        echo "Health check attempt $attempt failed"
                        sleep 3
                    done

                    echo "Deployment health checks failed"
                    exit 1
                '''
            }
        }
    }

    post {
        success {
            echo "CI/CD pipeline completed successfully"
            echo "Release: ${env.IMAGE_TAG}"
        }

        failure {
            echo "Pipeline failed. Review the console output."
            echo "Check containers using: docker ps -a"
            echo "Previous release metadata is saved as .env.previous when available."
        }

        always {
        }
    }
}

