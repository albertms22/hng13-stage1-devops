#!/bin/bash

################################################################################
# HNG13 Stage 2 - Automated Deployment Script
# This script automates the deployment of a Dockerized application
################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file with timestamp
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

################################################################################
# LOGGING FUNCTIONS
################################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

################################################################################
# ERROR HANDLING
################################################################################

cleanup_on_error() {
    log_error "Script failed at line $1"
    exit 1
}

trap 'cleanup_on_error $LINENO' ERR

################################################################################
# STEP 1: COLLECT USER INPUT
################################################################################

log "Starting deployment script..."
log "Collecting deployment parameters..."

# Git Repository URL
read -p "Enter Git Repository URL: " GIT_REPO
if [[ -z "$GIT_REPO" ]]; then
    log_error "Git repository URL cannot be empty!"
    exit 1
fi

# Personal Access Token
read -sp "Enter Personal Access Token (PAT): " GIT_PAT
echo
if [[ -z "$GIT_PAT" ]]; then
    log_error "Personal Access Token cannot be empty!"
    exit 1
fi

# Branch name (default: main)
read -p "Enter branch name [main]: " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}

# Remote server details
read -p "Enter remote server username: " SSH_USER
if [[ -z "$SSH_USER" ]]; then
    log_error "SSH username cannot be empty!"
    exit 1
fi

read -p "Enter remote server IP address: " SSH_HOST
if [[ -z "$SSH_HOST" ]]; then
    log_error "SSH host cannot be empty!"
    exit 1
fi

read -p "Enter SSH key path [~/.ssh/id_rsa]: " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

# Validate SSH key exists
if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found at $SSH_KEY"
    exit 1
fi

# Application port
read -p "Enter application container port [3000]: " APP_PORT
APP_PORT=${APP_PORT:-3000}

log "All parameters collected successfully!"

################################################################################
# STEP 2: CLONE REPOSITORY
################################################################################

log "Cloning repository from $GIT_REPO..."

# Extract repo name from URL
REPO_NAME=$(basename "$GIT_REPO" .git)
PROJECT_DIR="$HOME/$REPO_NAME"

# Create authenticated URL
AUTH_URL=$(echo "$GIT_REPO" | sed "s|https://|https://${GIT_PAT}@|")

if [[ -d "$PROJECT_DIR" ]]; then
    log_warning "Repository already exists. Pulling latest changes..."
    cd "$PROJECT_DIR"
    git pull origin "$GIT_BRANCH" >> "$LOG_FILE" 2>&1
else
    git clone "$AUTH_URL" "$PROJECT_DIR" >> "$LOG_FILE" 2>&1
    cd "$PROJECT_DIR"
fi

# Switch to specified branch
git checkout "$GIT_BRANCH" >> "$LOG_FILE" 2>&1
log "Repository cloned and switched to branch: $GIT_BRANCH"

################################################################################
# STEP 3: VERIFY DOCKERFILE
################################################################################

log "Verifying Docker configuration..."

if [[ ! -f "Dockerfile" ]] && [[ ! -f "docker-compose.yml" ]]; then
    log_error "No Dockerfile or docker-compose.yml found in repository!"
    exit 1
fi

log "Docker configuration verified successfully!"

################################################################################
# STEP 4: TEST SSH CONNECTION
################################################################################

log "Testing SSH connection to $SSH_HOST..."

if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SSH_HOST" "echo 'SSH connection successful'" >> "$LOG_FILE" 2>&1; then
    log_error "Failed to establish SSH connection to $SSH_HOST"
    exit 1
fi

log "SSH connection successful!"

################################################################################
# STEP 5: PREPARE REMOTE ENVIRONMENT
################################################################################

log "Preparing remote server environment..."

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << 'ENDSSH'
set -e

echo "Updating system packages..."
sudo apt-get update -y

echo "Installing required packages..."
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common nginx

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
else
    echo "Docker already installed"
fi

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose already installed"
fi

# Start and enable services
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl start nginx
sudo systemctl enable nginx

echo "Environment preparation complete!"
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"
echo "Nginx version: $(nginx -v 2>&1)"
ENDSSH

log "Remote environment prepared successfully!"

################################################################################
# STEP 6: TRANSFER PROJECT FILES
################################################################################

log "Transferring project files to remote server..."

REMOTE_PROJECT_DIR="/home/$SSH_USER/$REPO_NAME"

# Create remote directory
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_PROJECT_DIR"

# Transfer files using rsync (more efficient than scp)
rsync -avz --exclude '.git' -e "ssh -i $SSH_KEY" "$PROJECT_DIR/" "$SSH_USER@$SSH_HOST:$REMOTE_PROJECT_DIR/" >> "$LOG_FILE" 2>&1

log "Project files transferred successfully!"

################################################################################
# STEP 7: DEPLOY DOCKERIZED APPLICATION
################################################################################

log "Deploying Dockerized application..."

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
set -e
cd $REMOTE_PROJECT_DIR

echo "Stopping old containers (if any)..."
docker stop $REPO_NAME 2>/dev/null || true
docker rm $REPO_NAME 2>/dev/null || true

if [[ -f "docker-compose.yml" ]]; then
    echo "Using docker-compose..."
    docker-compose down 2>/dev/null || true
    docker-compose up -d --build
else
    echo "Using Dockerfile..."
    docker build -t $REPO_NAME:latest .
    docker run -d --name $REPO_NAME -p $APP_PORT:$APP_PORT --restart unless-stopped $REPO_NAME:latest
fi

echo "Waiting for container to be healthy..."
sleep 5

# Verify container is running
if docker ps | grep -q $REPO_NAME; then
    echo "Container is running successfully!"
    docker ps | grep $REPO_NAME
else
    echo "ERROR: Container failed to start!"
    docker logs $REPO_NAME
    exit 1
fi
ENDSSH

log "Application deployed successfully!"

################################################################################
# STEP 8: CONFIGURE NGINX REVERSE PROXY
################################################################################

log "Configuring Nginx reverse proxy..."

NGINX_CONFIG="/etc/nginx/sites-available/$REPO_NAME"

ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
set -e

echo "Creating Nginx configuration..."
sudo tee $NGINX_CONFIG > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable site
sudo ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/$REPO_NAME

# Remove default site if exists
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

echo "Nginx configured successfully!"
ENDSSH

log "Nginx reverse proxy configured successfully!"

################################################################################
# STEP 9: VALIDATE DEPLOYMENT
################################################################################

log "Validating deployment..."

# Test locally from remote server
ssh -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" bash << ENDSSH
set -e

echo "Testing local container access..."
if curl -f http://localhost:$APP_PORT > /dev/null 2>&1; then
    echo "✓ Container is accessible on port $APP_PORT"
else
    echo "✗ Container not accessible on port $APP_PORT"
    exit 1
fi

echo "Testing Nginx proxy..."
if curl -f http://localhost > /dev/null 2>&1; then
    echo "✓ Nginx proxy is working"
else
    echo "✗ Nginx proxy not working"
    exit 1
fi

echo "Container logs:"
docker logs $REPO_NAME --tail 20
ENDSSH

# Test from local machine
log "Testing external access..."
if curl -f "http://$SSH_HOST" > /dev/null 2>&1; then
    log "✓ Application is publicly accessible at http://$SSH_HOST"
else
    log_warning "Application might not be publicly accessible. Check firewall rules."
fi

################################################################################
# DEPLOYMENT SUMMARY
################################################################################

log "================================================"
log "DEPLOYMENT COMPLETED SUCCESSFULLY!"
log "================================================"
log "Repository: $GIT_REPO"
log "Branch: $GIT_BRANCH"
log "Remote Server: $SSH_USER@$SSH_HOST"
log "Application Port: $APP_PORT"
log "Access URL: http://$SSH_HOST"
log "Log File: $LOG_FILE"
log "================================================"

exit
