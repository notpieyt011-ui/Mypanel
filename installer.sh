#!/bin/bash

# ============================================
# AQUA PANEL - ONE CLICK INSTALLER
# ============================================
# Run: curl -sSL https://your-repo.com/install.sh | sudo bash
# Or: wget -qO- https://your-repo.com/install.sh | sudo bash
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Config
PANEL_DIR="/var/www/aqua-panel"
DB_NAME="aqua_panel"
DB_USER="aquapanel"
DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
SESSION_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
PANEL_PORT=3000
LOG_FILE="/var/log/aqua-panel-install.log"
GITHUB_RAW="https://raw.githubusercontent.com/yourusername/aqua-panel/main"

# ============================================
# BANNER
# ============================================
clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║         A Q U A   P A N E L   I N S T A L L E R         ║"
echo "║              One-Click Installation                      ║"
echo "║              Version 1.0.0                               ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ============================================
# CHECK ROOT
# ============================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] This script must be run as root!${NC}"
    echo -e "${YELLOW}Use: sudo bash install.sh${NC}"
    exit 1
fi

# ============================================
# HELPER FUNCTIONS
# ============================================
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
info() { echo -e "${BLUE}[i]${NC} $1"; log "INFO: $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; log "SUCCESS: $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; log "WARN: $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; log "ERROR: $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}\n"; }

# ============================================
# START INSTALLATION
# ============================================
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

section "Starting Aqua Panel Installation"
info "Log file: $LOG_FILE"

# ============================================
# STEP 1: SYSTEM UPDATE
# ============================================
section "Step 1/10: Updating System Packages"
apt update -y >> "$LOG_FILE" 2>&1 && apt upgrade -y >> "$LOG_FILE" 2>&1
success "System updated"

# ============================================
# STEP 2: INSTALL DEPENDENCIES
# ============================================
section "Step 2/10: Installing Required Packages"
apt install -y curl wget git unzip nginx build-essential openssl ufw >> "$LOG_FILE" 2>&1
success "Dependencies installed"

# ============================================
# STEP 3: INSTALL NODE.JS 22
# ============================================
section "Step 3/10: Installing Node.js 22.x"
if command -v node &> /dev/null; then
    warn "Node.js already installed: $(node -v)"
else
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >> "$LOG_FILE" 2>&1
    apt install -y nodejs >> "$LOG_FILE" 2>&1
    success "Node.js $(node -v) installed"
fi

# ============================================
# STEP 4: INSTALL MYSQL
# ============================================
section "Step 4/10: Installing MySQL Server"
if command -v mysql &> /dev/null; then
    warn "MySQL already installed"
else
    apt install -y mysql-server >> "$LOG_FILE" 2>&1
    systemctl start mysql >> "$LOG_FILE" 2>&1
    systemctl enable mysql >> "$LOG_FILE" 2>&1
    success "MySQL installed"
fi

# ============================================
# STEP 5: SETUP DATABASE
# ============================================
section "Step 5/10: Configuring Database"
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>/dev/null
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
success "Database configured"

# ============================================
# STEP 6: CREATE DIRECTORIES
# ============================================
section "Step 6/10: Creating Panel Directories"
mkdir -p "$PANEL_DIR"/{server/{config,routes,middleware,models,database},public/{css,js,images},uploads,logs,backups,ssl}
success "Directories created"

# ============================================
# STEP 7: DOWNLOAD & CREATE FILES
# ============================================
section "Step 7/10: Creating Panel Files"

cd "$PANEL_DIR"

# Download files from GitHub or create them
info "Creating server package.json..."
cat > "$PANEL_DIR/server/package.json" << 'PKGJSON'
{
  "name": "aqua-panel",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.21.0",
    "mysql2": "^3.11.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "dotenv": "^16.4.5",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "socket.io": "^4.7.5",
    "express-session": "^1.18.0",
    "compression": "^1.7.4",
    "multer": "^1.4.5-lts.1",
    "uuid": "^10.0.0",
    "express-rate-limit": "^7.4.0"
  }
}
PKGJSON

info "Creating .env file..."
cat > "$PANEL_DIR/server/.env" << EOF
PORT=$PANEL_PORT
NODE_ENV=production
DB_HOST=localhost
DB_PORT=3306
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASS
DB_NAME=$DB_NAME
JWT_SECRET=$JWT_SECRET
SESSION_SECRET=$SESSION_SECRET
TZ=Asia/Kolkata
EOF

info "Creating database config..."
cat > "$PANEL_DIR/server/config/database.js" << 'DBCONFIG'
const mysql = require('mysql2/promise');
require('dotenv').config();
const pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER || 'aquapanel',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'aqua_panel',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});
const query = async (sql, params) => { const [rows] = await pool.execute(sql, params); return rows; };
const testConnection = async () => { const c = await pool.getConnection(); c.release(); return true; };
const closePool = async () => { await pool.end(); };
module.exports = { pool, query, testConnection, closePool };
DBCONFIG

info "Creating server.js..."
cat > "$PANEL_DIR/server/server.js" << 'SERVERJS'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const compression = require('compression');
const path = require('path');
const session = require('express-session');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(compression());
app.use(morgan('combined'));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(session({ secret: process.env.SESSION_SECRET || 'secret', resave: false, saveUninitialized: false, cookie: { maxAge: 86400000 } }));

app.use(express.static(path.join(__dirname, '..', 'public')));
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.get('/api/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

app.get('/', (req, res) => res.sendFile(path.join(__dirname, '..', 'landing.html')));
app.get('/register', (req, res) => res.sendFile(path.join(__dirname, '..', 'register.html')));
app.get('/login', (req, res) => res.sendFile(path.join(__dirname, '..', 'login.html')));
app.get('/dashboard', (req, res) => res.sendFile(path.join(__dirname, '..', 'dashboard.html')));
app.get('/console', (req, res) => res.sendFile(path.join(__dirname, '..', 'console.html')));
app.get('/admin', (req, res) => res.sendFile(path.join(__dirname, '..', 'admin.html')));

io.on('connection', (socket) => { socket.on('disconnect', () => {}); });

app.use((err, req, res, next) => { res.status(500).json({ error: 'Server error' }); });

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Aqua Panel running on port ${PORT}`));
SERVERJS

success "Server files created"

# ============================================
# STEP 8: INSTALL NPM & PM2
# ============================================
section "Step 8/10: Installing Dependencies"
cd "$PANEL_DIR/server"
npm install --production >> "$LOG_FILE" 2>&1
npm install -g pm2 >> "$LOG_FILE" 2>&1
success "Dependencies installed"

# ============================================
# STEP 9: CONFIGURE NGINX
# ============================================
section "Step 9/10: Configuring Nginx"
cat > /etc/nginx/sites-available/aqua-panel << 'NGINX'
server {
    listen 80;
    server_name _;
    client_max_body_size 100M;
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }
    location /socket.io/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
ln -sf /etc/nginx/sites-available/aqua-panel /etc/nginx/sites-enabled/ 2>/dev/null
rm -f /etc/nginx/sites-enabled/default 2>/dev/null
nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1
success "Nginx configured"

# ============================================
# STEP 10: START PANEL
# ============================================
section "Step 10/10: Starting Aqua Panel"
cd "$PANEL_DIR/server"
pm2 delete aqua-panel 2>/dev/null || true
pm2 start server.js --name aqua-panel --time >> "$LOG_FILE" 2>&1
pm2 save >> "$LOG_FILE" 2>&1
pm2 startup systemd -u root --hp /root >> "$LOG_FILE" 2>&1
success "Panel started"

# ============================================
# FIREWALL
# ============================================
ufw allow 22/tcp 2>/dev/null
ufw allow 80/tcp 2>/dev/null
ufw allow 443/tcp 2>/dev/null
ufw allow $PANEL_PORT/tcp 2>/dev/null
ufw --force enable 2>/dev/null

# ============================================
# SAVE CREDENTIALS
# ============================================
IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
CRED_FILE="/root/aqua-panel-credentials.txt"

cat > "$CRED_FILE" << EOF
============================================
   AQUA PANEL - Installation Complete
============================================
Panel URL: http://$IP
Admin: First registered user gets admin
Database: $DB_NAME
User: $DB_USER
Password: $DB_PASS
============================================
EOF
chmod 600 "$CRED_FILE"

# ============================================
# COMPLETE
# ============================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║         INSTALLATION COMPLETE!                            ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Panel URL:${NC} ${CYAN}http://$IP${NC}"
echo -e "${BOLD}First user to register becomes ADMIN!${NC}"
echo ""
echo -e "${BOLD}Database:${NC}"
echo -e "  Name: ${YELLOW}$DB_NAME${NC}"
echo -e "  User: ${YELLOW}$DB_USER${NC}"
echo -e "  Pass: ${YELLOW}$DB_PASS${NC}"
echo ""
echo -e "${BOLD}Credentials saved:${NC} ${YELLOW}$CRED_FILE${NC}"
echo ""
echo -e "${BOLD}Commands:${NC}"
echo -e "  pm2 status              - Check status"
echo -e "  pm2 logs aqua-panel     - View logs"
echo -e "  pm2 restart aqua-panel  - Restart panel"
echo ""

exit 0