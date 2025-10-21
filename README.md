# Automated Deployment Script - HNG13 Stage 1

## Overview
This Bash script automates the complete deployment of a Dockerized application to a remote Linux server, including environment setup, Docker configuration, and Nginx reverse proxy setup.

## Features
✅ Interactive parameter collection with validation  
✅ Automated Git repository cloning with PAT authentication  
✅ Remote server environment preparation  
✅ Docker and Docker Compose installation  
✅ Automated container deployment  
✅ Nginx reverse proxy configuration  
✅ Comprehensive error handling and logging  
✅ Deployment validation and health checks  
✅ Idempotent execution (safe to re-run)  

## Prerequisites

### Local Machine Requirements
- Bash shell (Linux/macOS/WSL)
- Git
- SSH client
- rsync

### Remote Server Requirements
- Ubuntu 20.04+ or similar Debian-based Linux
- SSH access with key-based authentication
- Sudo privileges
- Ports 22, 80, and your application port open in firewall

### Repository Requirements
- Must contain either `Dockerfile` or `docker-compose.yml`
- Application must expose a port that can be accessed

## Usage

### 1. Make the script executable
```bash
chmod +x deploy.sh
```

### 2. Run the script
```bash
./deploy.sh
```

### 3. Provide the required information when prompted:
- **Git Repository URL**: Your GitHub/GitLab repository URL (HTTPS)
- **Personal Access Token**: GitHub PAT with repo access
- **Branch Name**: Target branch (default: main)
- **SSH Username**: Remote server username (e.g., ubuntu, root)
- **Server IP**: Public IP address of your remote server
- **SSH Key Path**: Path to your private SSH key (default: ~/.ssh/id_rsa)
- **Application Port**: Internal container port (default: 3000)

## Example Interaction

```bash
./deploy.sh

Enter Git Repository URL: https://github.com/username/my-app.git
Enter Personal Access Token (PAT): ghp_xxxxxxxxxxxxxxxxxxxx
Enter branch name [main]: main
Enter remote server username: ubuntu
Enter remote server IP address: 54.123.45.67
Enter SSH key path [~/.ssh/id_rsa]: ~/.ssh/my-key.pem
Enter application container port [3000]: 8080
```

## What the Script Does

### Step 1: Parameter Collection
Collects and validates all necessary deployment parameters from user input.

### Step 2: Repository Cloning
- Clones the Git repository using PAT authentication
- If repository exists, pulls latest changes
- Switches to specified branch

### Step 3: Docker Configuration Verification
Checks for presence of `Dockerfile` or `docker-compose.yml` in the repository.

### Step 4: SSH Connection Test
Validates SSH connectivity to the remote server before proceeding.

### Step 5: Remote Environment Setup
On the remote server:
- Updates system packages
- Installs Docker, Docker Compose, and Nginx
- Adds user to Docker group
- Enables and starts required services

### Step 6: File Transfer
Transfers project files from local machine to remote server using rsync.

### Step 7: Container Deployment
- Stops and removes old containers (if any)
- Builds Docker image from Dockerfile or uses docker-compose
- Runs container with proper configuration
- Validates container health

### Step 8: Nginx Configuration
- Creates Nginx reverse proxy configuration
- Forwards traffic from port 80 to container port
- Tests and reloads Nginx

### Step 9: Validation
- Tests container accessibility locally
- Tests Nginx proxy functionality
- Attempts external access validation
- Displays container logs

## Logging
All operations are logged to a timestamped file: `deploy_YYYYMMDD_HHMMSS.log`

Logs include:
- Timestamps for all operations
- Success/failure status
- Error messages with context
- Command outputs

## Error Handling
The script includes comprehensive error handling:
- Exits on first error (`set -e`)
- Validates all user inputs
- Checks prerequisites before proceeding
- Provides meaningful error messages
- Logs all failures for debugging

## Idempotency
The script is designed to be safely re-run:
- Pulls latest changes if repository exists
- Stops old containers before deploying new ones
- Overwrites Nginx configuration
- No duplicate resources created

## Security Considerations
- SSH key-based authentication (no password prompts)
- PAT is not logged or displayed
- Proper file permissions maintained
- User added to Docker group for non-root operation

## Troubleshooting

### SSH Connection Failed
- Verify SSH key permissions: `chmod 400 /path/to/key.pem`
- Ensure SSH port (22) is open in firewall
- Verify correct username for the server OS

### Container Not Starting
- Check Docker logs: `docker logs <container-name>`
- Verify Dockerfile syntax
- Ensure application port is correctly specified

### Nginx Proxy Not Working
- Test Nginx config: `sudo nginx -t`
- Check Nginx error logs: `sudo tail -f /var/log/nginx/error.log`
- Verify container is listening on specified port

### Application Not Accessible Externally
- Check security group/firewall allows HTTP (port 80)
- Verify Nginx is running: `sudo systemctl status nginx`
- Test locally first: `curl http://localhost`

## Tested Environments
- Ubuntu 22.04 LTS
- Ubuntu 20.04 LTS
- Debian 11

## Author
Created for HNG13 DevOps Internship - Stage 1

## License
MIT License - Feel free to use and modify for your needs.
