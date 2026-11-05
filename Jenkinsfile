
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    environment {
        AWS_REGION = 'ap-south-1'
        PROJECT = 'microdev'

        // Replace with Terraform's EC2 public IP.
        EC2_HOST = '13.233.119.105'
    }

    stages {

        stage('Checkout Source') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Release') {
            steps {
                script {
                    def shortCommit = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG =
                        "${env.BUILD_NUMBER}-${shortCommit}"
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
                    env.REGISTRY =
                        "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
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

                    export GRAFANA_ADMIN_PASSWORD=dummy-validation-value

                    docker compose \
                      -f deploy/compose.yaml \
                      config --quiet

                    echo "Configuration validation passed"
                '''
            }
        }

        stage('Build Docker Images') {
            steps {
                sh '''
                    set -eu

                    for service in user product order
                    do
                        echo "Building $service service"

                        docker build \
                          -t "$REGISTRY/$PROJECT-$service:$IMAGE_TAG" \
                          "./$service-service"
                    done
                '''
            }
        }

        stage('Run Application Tests') {
            steps {
                sh '''
                    set -eu

                    for service in user product order
                    do
                        echo "Testing $service service"

                        docker run --rm \
                          --entrypoint python \
                          "$REGISTRY/$PROJECT-$service:$IMAGE_TAG" \
                          -m unittest discover \
                          -s /app/tests \
                          -v
                    done
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
                        set -eu

                        aws ecr get-login-password \
                          --region "$AWS_REGION" |
                        docker login \
                          --username AWS \
                          --password-stdin \
                          "$REGISTRY"

                        for service in user product order
                        do
                            docker push \
                              "$REGISTRY/$PROJECT-$service:$IMAGE_TAG"
                        done

                        docker logout "$REGISTRY"
                    '''
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh '''
                        set -eu
                        umask 077

                        printf 'AWS_ACCOUNT_ID=%s\\nAWS_REGION=%s\\nIMAGE_TAG=%s\\n' \
                          "$AWS_ACCOUNT_ID" \
                          "$AWS_REGION" \
                          "$IMAGE_TAG" > deploy/.env

                        REMOTE="ubuntu@$EC2_HOST"

                        ssh -o BatchMode=yes "$REMOTE" \
                          'mkdir -p /opt/microdev &&
                           if [ -f /opt/microdev/.env ]; then
                             cp /opt/microdev/.env /opt/microdev/.env.previous
                           fi'

                        scp -o BatchMode=yes \
                          deploy/compose.yaml \
                          deploy/nginx.conf \
                          deploy/prometheus.yml \
                          deploy/.env \
                          "$REMOTE:/opt/microdev/"

                        scp -o BatchMode=yes -r \
                          deploy/grafana \
                          "$REMOTE:/opt/microdev/"

                        ssh -o BatchMode=yes "$REMOTE" '
                          set -eu

                          cd /opt/microdev
                          chmod 600 .env

                          ACCOUNT_ID=$(aws sts get-caller-identity \
                            --query Account --output text)

                          aws ecr get-login-password \
                            --region ap-south-1 |
                          docker login \
                            --username AWS \
                            --password-stdin \
                            "$ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com"

                          docker compose \
                            --env-file .env \
                            --env-file .secrets.env \
                            pull

                          docker compose \
                            --env-file .env \
                            --env-file .secrets.env \
                            up -d --remove-orphans
                        '
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh '''
                        set -eu

                        ssh -o BatchMode=yes \
                          "ubuntu@$EC2_HOST" '
                          set -eu

                          cd /opt/microdev

                          for attempt in $(seq 1 30)
                          do
                            if curl -fsS http://127.0.0.1/users/health \
                               >/dev/null &&
                               curl -fsS http://127.0.0.1/products/health \
                               >/dev/null &&
                               curl -fsS http://127.0.0.1/orders/health \
                               >/dev/null
                            then
                              echo "All microservices are healthy"
                              exit 0
                            fi

                            echo "Waiting for services..."
                            sleep 5
                          done

                          docker compose \
                            --env-file .env \
                            --env-file .secrets.env \
                            ps

                          exit 1
                        '
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "CI/CD pipeline completed successfully."
            echo "Deployed release: ${env.IMAGE_TAG}"
        }

        failure {
            echo "Pipeline failed. Review the failed stage."
            echo "Previous release can be restored using .env.previous."
        }

        always {
            cleanWs()
        }
    }
}
