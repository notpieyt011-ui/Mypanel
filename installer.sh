#!/bin/bash

###############################################################################
# AQUA PANEL - Premium Minecraft Server Management Panel
# One-Click Installation Script
# Version: 1.0.0
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration Variables
PANEL_DIR="/var/www/aqua-panel"
PANEL_USER="aquapanel"
DB_NAME="aqua_panel"
DB_USER="aquapanel_user"
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
JWT_SECRET=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 64)
SESSION_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
ADMIN_EMAIL="admin@aquapanel.com"
ADMIN_PASSWORD="Admin@123"
PANEL_PORT=3000
NGINX_PORT=80

# Log file
LOG_FILE="/var/log/aqua-panel-install.log"

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║         🌊  A Q U A   P A N E L  🌊                      ║"
    echo "║     Premium Minecraft Server Management Panel            ║"
    echo "║                                                           ║"
    echo "║         One-Click Installation Script                     ║"
    echo "║         Version 1.0.0                                     ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Log function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Error message
error() {
    echo -e "${RED}❌ $1${NC}"
    log "ERROR: $1"
    exit 1
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root! Use: sudo bash install.sh"
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        info "Detected OS: $OS $VER"
    else
        error "Cannot detect OS. Supported: Ubuntu 20.04/22.04, Debian 11/12"
    fi
    
    # Check if supported
    if [[ "$OS" != "Ubuntu" ]] && [[ "$OS" != "Debian GNU/Linux" ]]; then
        warning "This script is optimized for Ubuntu/Debian. Proceed with caution."
    fi
}

# Check system requirements
check_requirements() {
    info "Checking system requirements..."
    
    # Check RAM
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 512 ]; then
        warning "Less than 512MB RAM detected ($TOTAL_RAM MB). Panel may not run optimally."
    else
        success "RAM: ${TOTAL_RAM}MB"
    fi
    
    # Check Disk
    FREE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_DISK" -lt 5 ]; then
        warning "Less than 5GB free disk space. Clean up before continuing."
    else
        success "Free Disk: ${FREE_DISK}GB"
    fi
    
    # Check CPU
    CPU_CORES=$(nproc)
    success "CPU Cores: $CPU_CORES"
}

# Update system
update_system() {
    info "Updating system packages..."
    apt update -y >> "$LOG_FILE" 2>&1
    apt upgrade -y >> "$LOG_FILE" 2>&1
    success "System updated"
}

# Install dependencies
install_dependencies() {
    info "Installing required dependencies..."
    
    # Install essential packages
    apt install -y curl wget git unzip zip tar nginx certbot python3-certbot-nginx ufw >> "$LOG_FILE" 2>&1
    
    # Install build tools
    apt install -y build-essential gcc g++ make >> "$LOG_FILE" 2>&1
    
    success "Dependencies installed"
}

# Install Node.js
install_nodejs() {
    info "Installing Node.js 18.x..."
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        warning "Node.js already installed: $NODE_VERSION"
        read -p "Reinstall? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >> "$LOG_FILE" 2>&1
    apt install -y nodejs >> "$LOG_FILE" 2>&1
    
    success "Node.js $(node -v) installed"
    success "NPM $(npm -v) installed"
}

# Install MySQL
install_mysql() {
    info "Installing MySQL Server..."
    
    if command -v mysql &> /dev/null; then
        warning "MySQL already installed"
        read -p "Reinstall? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    apt install -y mysql-server >> "$LOG_FILE" 2>&1
    
    # Start MySQL
    systemctl start mysql
    systemctl enable mysql
    
    success "MySQL installed and started"
}

# Install PM2
install_pm2() {
    info "Installing PM2 Process Manager..."
    
    if command -v pm2 &> /dev/null; then
        success "PM2 already installed"
        return
    fi
    
    npm install -g pm2 >> "$LOG_FILE" 2>&1
    
    success "PM2 installed"
}

# Configure MySQL Database
setup_database() {
    info "Configuring MySQL Database..."
    
    # Generate secure password
    DB_ROOT_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    # Secure MySQL installation
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS';" 2>/dev/null || true
    
    # Create database and user
    mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    success "Database configured"
}

# Create panel directory
create_directories() {
    info "Creating panel directories..."
    
    mkdir -p "$PANEL_DIR"
    mkdir -p "$PANEL_DIR/public/css"
    mkdir -p "$PANEL_DIR/public/js"
    mkdir -p "$PANEL_DIR/public/images"
    mkdir -p "$PANEL_DIR/routes"
    mkdir -p "$PANEL_DIR/models"
    mkdir -p "$PANEL_DIR/middleware"
    mkdir -p "$PANEL_DIR/config"
    mkdir -p "$PANEL_DIR/views"
    mkdir -p "$PANEL_DIR/database"
    mkdir -p "$PANEL_DIR/uploads"
    mkdir -p "$PANEL_DIR/logs"
    
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 "$PANEL_DIR"
    
    success "Directories created"
}

# Generate package.json
generate_package_json() {
    info "Generating package.json..."
    
    cat > "$PANEL_DIR/package.json" <<EOF
{
  "name": "aqua-panel",
  "version": "1.0.0",
  "description": "Aqua Panel - Premium Minecraft Server Management",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ejs": "^3.1.9",
    "mysql2": "^3.6.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "dotenv": "^16.3.1",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.4",
    "morgan": "^1.10.0",
    "multer": "^1.4.5-lts.1",
    "socket.io": "^4.7.2",
    "express-session": "^1.17.3",
    "compression": "^1.7.4",
    "uuid": "^9.0.0"
  }
}
EOF
    
    success "package.json created"
}

# Generate .env file
generate_env() {
    info "Generating environment configuration..."
    
    cat > "$PANEL_DIR/.env" <<EOF
# Server Configuration
PORT=$PANEL_PORT
NODE_ENV=production
APP_NAME=Aqua Panel
APP_URL=http://localhost:$PANEL_PORT

# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME

# JWT Secret
JWT_SECRET=$JWT_SECRET
JWT_EXPIRE=30d

# Session
SESSION_SECRET=$SESSION_SECRET

# Admin Default Credentials
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Upload Limits
MAX_FILE_SIZE=104857600
UPLOAD_PATH=./uploads

# Security
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=100
EOF
    
    success ".env file created"
}

# Generate server.js
generate_server() {
    info "Generating main server file..."
    
    cat > "$PANEL_DIR/server.js" <<'SERVEREOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const path = require('path');
const session = require('express-session');
const { createServer } = require('http');
const { Server } = require('socket.io');

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer);

// Database
const db = require('./config/database');

// Middleware
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors());
app.use(compression());
app.use(morgan('combined'));
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Rate Limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100
});
app.use('/api/', limiter);

// Session
app.use(session({
    secret: process.env.SESSION_SECRET || 'secret',
    resave: false,
    saveUninitialized: false,
    cookie: { maxAge: 24 * 60 * 60 * 1000 }
}));

// Static Files
app.use(express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// View Engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Database connection check
app.get('/api/health', async (req, res) => {
    try {
        await db.query('SELECT 1');
        res.json({ status: 'healthy', database: 'connected' });
    } catch (err) {
        res.status(500).json({ status: 'unhealthy', database: 'disconnected' });
    }
});

// Auth Routes
app.post('/api/auth/register', async (req, res) => {
    try {
        const { username, email, password } = req.body;
        
        // Check if first user
        const [users] = await db.query('SELECT COUNT(*) as count FROM users');
        const isFirstUser = users[0].count === 0;
        
        const bcrypt = require('bcryptjs');
        const hashedPassword = await bcrypt.hash(password, 10);
        
        const [result] = await db.query(
            'INSERT INTO users (username, email, password, role, is_first_user) VALUES (?, ?, ?, ?, ?)',
            [username, email, hashedPassword, isFirstUser ? 'admin' : 'user', isFirstUser]
        );
        
        const jwt = require('jsonwebtoken');
        const token = jwt.sign(
            { id: result.insertId, role: isFirstUser ? 'admin' : 'user' },
            process.env.JWT_SECRET,
            { expiresIn: '30d' }
        );
        
        res.json({ 
            success: true, 
            token,
            isFirstUser,
            message: isFirstUser ? 'First user registered as ADMIN!' : 'Registration successful'
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

app.post('/api/auth/login', async (req, res) => {
    try {
        const { email, password } = req.body;
        const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
        
        if (users.length === 0) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        const bcrypt = require('bcryptjs');
        const validPassword = await bcrypt.compare(password, users[0].password);
        
        if (!validPassword) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }
        
        const jwt = require('jsonwebtoken');
        const token = jwt.sign(
            { id: users[0].id, role: users[0].role },
            process.env.JWT_SECRET,
            { expiresIn: '30d' }
        );
        
        res.json({ success: true, token, user: users[0] });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Serve main HTML page
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Socket.io
io.on('connection', (socket) => {
    console.log('User connected:', socket.id);
    socket.on('disconnect', () => console.log('User disconnected:', socket.id));
});

// Error handler
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ error: 'Internal Server Error' });
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
    console.log(`🌊 Aqua Panel running on port ${PORT}`);
});
SERVEREOF
    
    success "server.js created"
}

# Generate database config
generate_db_config() {
    cat > "$PANEL_DIR/config/database.js" <<'DBEOF'
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 3306,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
});

pool.getConnection()
    .then(conn => {
        console.log('✅ Database connected');
        conn.release();
    })
    .catch(err => {
        console.error('❌ Database connection failed:', err.message);
    });

module.exports = pool;
DBEOF
}

# Generate database schema
generate_schema() {
    cat > "$PANEL_DIR/database/schema.sql" <<'SQLEOF'
CREATE DATABASE IF NOT EXISTS aqua_panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE aqua_panel;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin', 'user') DEFAULT 'user',
    is_first_user BOOLEAN DEFAULT FALSE,
    avatar VARCHAR(255) DEFAULT NULL,
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    user_id INT NOT NULL,
    node_id INT,
    memory INT DEFAULT 4096,
    cpu INT DEFAULT 200,
    disk INT DEFAULT 51200,
    status ENUM('installing', 'running', 'stopped', 'error') DEFAULT 'installing',
    expires_at DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS nodes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    fqdn VARCHAR(255) NOT NULL,
    total_memory INT NOT NULL,
    total_disk INT NOT NULL,
    port_range_start VARCHAR(50),
    port_range_end VARCHAR(50),
    status ENUM('active', 'inactive') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS locations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    flag VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS api_keys (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    key_value VARCHAR(64) UNIQUE NOT NULL,
    description VARCHAR(255),
    permissions TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

INSERT INTO settings (setting_key, setting_value) VALUES 
('panel_theme', 'purple'),
('panel_font', 'Inter'),
('glow_intensity', '50')
ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value);
SQLEOF
}

# Generate Nginx config
generate_nginx_config() {
    cat > "/etc/nginx/sites-available/aqua-panel" <<NGINXEOF
server {
    listen 80;
    server_name _;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://localhost:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /socket.io/ {
        proxy_pass http://localhost:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/aqua-panel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl restart nginx
}

# Initialize database
init_database() {
    info "Initializing database..."
    mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "$PANEL_DIR/database/schema.sql" 2>> "$LOG_FILE"
    success "Database initialized"
}

# Install npm dependencies
install_npm_deps() {
    info "Installing NPM dependencies..."
    cd "$PANEL_DIR"
    npm install --production >> "$LOG_FILE" 2>&1
    success "NPM dependencies installed"
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."
    
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow $PANEL_PORT/tcp
    
    success "Firewall configured"
}

# Start application
start_application() {
    info "Starting Aqua Panel..."
    
    cd "$PANEL_DIR"
    
    # Stop if already running
    pm2 delete aqua-panel 2>/dev/null || true
    
    # Start with PM2
    pm2 start server.js --name aqua-panel --time --log "$PANEL_DIR/logs/app.log"
    pm2 save
    pm2 startup systemd -u root --hp /root
    
    success "Application started"
}

# Save credentials
save_credentials() {
    CRED_FILE="/root/aqua-panel-credentials.txt"
    
    cat > "$CRED_FILE" <<EOF
===========================================
   AQUA PANEL - Installation Complete!
===========================================

Panel URL: http://$(curl -s ifconfig.me):$PANEL_PORT
Admin Email: $ADMIN_EMAIL
Admin Password: $ADMIN_PASSWORD

Database Info:
  Database: $DB_NAME
  Username: $DB_USER
  Password: $DB_PASSWORD

Installation Directory: $PANEL_DIR
Log File: $LOG_FILE

===========================================
   SAVE THESE CREDENTIALS SECURELY!
===========================================

First registered user automatically becomes ADMIN!
EOF

    chmod 600 "$CRED_FILE"
}

# Final summary
show_summary() {
    SERVER_IP=$(curl -s ifconfig.me)
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║         🎉  INSTALLATION COMPLETE!  🎉                   ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📱 Panel URL:${NC} http://$SERVER_IP:$PANEL_PORT"
    echo -e "${CYAN}👤 Admin Email:${NC} $ADMIN_EMAIL"
    echo -e "${CYAN}🔑 Admin Password:${NC} $ADMIN_PASSWORD"
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: First registered user becomes ADMIN!${NC}"
    echo ""
    echo -e "${WHITE}📁 Installation Directory:${NC} $PANEL_DIR"
    echo -e "${WHITE}📄 Credentials Saved:${NC} /root/aqua-panel-credentials.txt"
    echo -e "${WHITE}📋 Log File:${NC} $LOG_FILE"
    echo ""
    echo -e "${GREEN}Commands:${NC}"
    