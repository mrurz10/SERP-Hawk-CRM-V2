#!/bin/bash
set -e
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "=================================================="
echo "Starting SonarQube provisioning: $(date)"
echo "=================================================="

SONARQUBE_VERSION="${sonarqube_version}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD_SSM_PARAM="${db_password_ssm_param}"
AWS_REGION="${aws_region}"
SONAR_INSTALL_DIR="/opt/sonarqube"

echo ">>> Step 1: System update"
apt-get update -y
apt-get upgrade -y

echo ">>> Step 2: Install AWS CLI v2 (official installer - apt's awscli package is unreliable on recent Ubuntu)"
apt-get install -y unzip curl
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws
cd /

echo ">>> Step 3: Fetch DB password securely from SSM Parameter Store"
# Authenticates via this instance's attached IAM role - no access keys on disk.
DB_PASSWORD=$(aws ssm get-parameter \
  --name "$DB_PASSWORD_SSM_PARAM" \
  --with-decryption \
  --region "$AWS_REGION" \
  --query "Parameter.Value" \
  --output text)

if [ -z "$DB_PASSWORD" ]; then
  echo "ERROR: Failed to fetch DB password from SSM ($DB_PASSWORD_SSM_PARAM). Check IAM role permissions and region."
  exit 1
fi
echo "Successfully retrieved DB password from SSM (value not logged)."

echo ">>> Step 4: Kernel settings required by Elasticsearch (used internally by SonarQube)"
sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" >> /etc/sysctl.conf
sysctl -p

echo ">>> Step 5: Raise file descriptor / process limits"
cat >> /etc/security/limits.conf << 'LIMITSEOF'
sonar   -   nofile   65536
sonar   -   nproc    4096
LIMITSEOF

echo ">>> Step 6: Install Java 17, PostgreSQL, and Nginx"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openjdk-17-jdk \
  postgresql \
  postgresql-contrib \
  nginx

echo ">>> Step 7: Start and configure PostgreSQL"
systemctl enable postgresql
systemctl start postgresql

sudo -u postgres psql -c "CREATE USER $${DB_USER} WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE $${DB_NAME} OWNER $${DB_USER};"

echo ">>> Step 8: Download and extract SonarQube"
cd /opt
wget -q "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-$SONARQUBE_VERSION.zip"
unzip -q "sonarqube-$SONARQUBE_VERSION.zip"
mv "sonarqube-$SONARQUBE_VERSION" sonarqube
rm "sonarqube-$SONARQUBE_VERSION.zip"

echo ">>> Step 9: Create dedicated non-root 'sonar' user"
useradd --system --no-create-home --shell /bin/false sonar || true
chown -R sonar:sonar "$SONAR_INSTALL_DIR"

echo ">>> Step 10: Configure SonarQube database connection"
cat >> "$SONAR_INSTALL_DIR/conf/sonar.properties" << PROPSEOF

# --- Added by provisioning script ---
sonar.jdbc.username=$${DB_USER}
sonar.jdbc.password=$DB_PASSWORD
sonar.jdbc.url=jdbc:postgresql://localhost:5432/$${DB_NAME}
sonar.web.host=0.0.0.0
sonar.web.port=9000
PROPSEOF

echo ">>> Step 11: Create systemd service"
cat > /etc/systemd/system/sonarqube.service << SERVICEEOF
[Unit]
Description=SonarQube service
After=network.target postgresql.service

[Service]
Type=forking
User=sonar
Group=sonar
ExecStart=$SONAR_INSTALL_DIR/bin/linux-x86-64/sonar.sh start
ExecStop=$SONAR_INSTALL_DIR/bin/linux-x86-64/sonar.sh stop
Restart=on-failure
LimitNOFILE=65536
LimitNPROC=4096
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable sonarqube

echo ">>> Step 12: Start SonarQube (may take 1-3 minutes to become healthy)"
systemctl start sonarqube

echo ">>> Step 13: Configure Nginx as a reverse proxy (port 80 -> 9000)"
cat > /etc/nginx/sites-available/sonarqube << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
NGINXEOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/sonarqube /etc/nginx/sites-enabled/sonarqube
nginx -t
systemctl restart nginx
systemctl enable nginx

echo ">>> Step 14: Install sonar-scanner CLI system-wide"
cd /opt
wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip
unzip -q sonar-scanner-cli-5.0.1.3006-linux.zip
mv sonar-scanner-5.0.1.3006-linux sonar-scanner
rm sonar-scanner-cli-5.0.1.3006-linux.zip
ln -sf /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner

echo ">>> Step 15: Wait for SonarQube API to respond (up to 5 minutes)"
for i in $(seq 1 30); do
  STATUS=$(curl -s http://localhost:9000/api/system/status | grep -o '"status":"[A-Z]*"' | cut -d'"' -f4 || echo "DOWN")
  echo "  Attempt $i: status=$STATUS"
  if [ "$STATUS" == "UP" ]; then
    echo "  SonarQube is UP!"
    break
  fi
  sleep 10
done

echo "=================================================="
echo "Provisioning complete: $(date)"
echo "Access SonarQube at: http://<THIS_INSTANCE_ELASTIC_IP>"
echo "Default login: admin / admin (you will be forced to change it)"
echo "Full log available at: /var/log/user-data.log"
echo "=================================================="
