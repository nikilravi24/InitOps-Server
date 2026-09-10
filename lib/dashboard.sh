#!/usr/bin/env bash
# Dashboard & Service Discovery for InitOps-Server
# Unified web dashboard, service registry, and API

# ============================================================================
# DASHBOARD CONFIGURATION
# ============================================================================

DASHBOARD_PORT="${DASHBOARD_PORT:-8081}"
DASHBOARD_DIR="/opt/initops-dashboard"
DASHBOARD_TEMPLATES_DIR="$DASHBOARD_DIR/templates"
DASHBOARD_STATIC_DIR="$DASHBOARD_DIR/static"

# ============================================================================
# DASHBOARD SERVER (using Python for simplicity)
# ============================================================================

# Create dashboard HTML template
dashboard_create_template() {
    mkdir -p "$DASHBOARD_TEMPLATES_DIR" "$DASHBOARD_STATIC_DIR"/{css,js}
    
    # Main HTML template
    cat > "$DASHBOARD_TEMPLATES_DIR/index.html" << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>InitOps-Server Dashboard</title>
    <link rel="stylesheet" href="/static/css/dashboard.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🚀</text></svg>">
</head>
<body>
    <div class="dashboard">
        <header class="header">
            <div class="logo">
                <span class="icon">🚀</span>
                <h1>InitOps-Server</h1>
            </div>
            <div class="system-info">
                <span id="hostname"></span>
                <span id="uptime"></span>
                <span id="last-updated"></span>
            </div>
        </header>
        
        <main class="main">
            <div class="stats-bar" id="stats-bar">
                <!-- Populated by JS -->
            </div>
            
            <div class="services-grid" id="services-grid">
                <!-- Populated by JS -->
            </div>
        </main>
        
        <footer class="footer">
            <p>InitOps-Server v<span id="version">-</span> | <a href="/api/health" target="_blank">API Health</a> | <a href="/api/services" target="_blank">Services JSON</a></p>
        </footer>
    </div>
    
    <script src="/static/js/dashboard.js"></script>
    <script>
        // Initialize dashboard
        Dashboard.init({
            apiBase: '/api',
            refreshInterval: 30000
        });
    </script>
</body>
</html>
HTML_EOF

    # CSS
    cat > "$DASHBOARD_STATIC_DIR/css/dashboard.css" << 'CSS_EOF'
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
    --bg-primary: #0d1117;
    --bg-secondary: #161b22;
    --bg-tertiary: #21262d;
    --border: #30363d;
    --text-primary: #e6edf3;
    --text-secondary: #8b949e;
    --accent: #58a6ff;
    --accent-hover: #79b8ff;
    --success: #3fb950;
    --warning: #d29922;
    --error: #f85149;
    --card-bg: #161b22;
    --card-hover: #1f2428;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    min-height: 100vh;
    line-height: 1.5;
}

.dashboard {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
}

.header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem 2rem;
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border);
}

.logo {
    display: flex;
    align-items: center;
    gap: 0.75rem;
}

.logo .icon { font-size: 2rem; }
.logo h1 { font-size: 1.5rem; font-weight: 600; background: linear-gradient(135deg, var(--accent), #a371f7); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }

.system-info {
    display: flex;
    gap: 1.5rem;
    font-size: 0.875rem;
    color: var(--text-secondary);
}

.main {
    flex: 1;
    padding: 2rem;
    max-width: 1400px;
    margin: 0 auto;
    width: 100%;
}

.stats-bar {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
    margin-bottom: 2rem;
}

.stat-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.25rem;
    transition: all 0.2s;
}

.stat-card:hover {
    border-color: var(--accent);
    background: var(--card-hover);
}

.stat-card .label {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-secondary);
    margin-bottom: 0.5rem;
}

.stat-card .value {
    font-size: 2rem;
    font-weight: 600;
}

.stat-card .value.healthy { color: var(--success); }
.stat-card .value.unhealthy { color: var(--error); }
.stat-card .value.warning { color: var(--warning); }

.services-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 1rem;
}

.service-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 1.25rem;
    transition: all 0.2s;
    position: relative;
    overflow: hidden;
}

.service-card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
    background: var(--border);
}

.service-card.healthy::before { background: var(--success); }
.service-card.unhealthy::before { background: var(--error); }
.service-card.warning::before { background: var(--warning); }
.service-card.unknown::before { background: var(--text-secondary); }

.service-card:hover {
    border-color: var(--accent);
    background: var(--card-hover);
    transform: translateY(-2px);
    box-shadow: 0 8px 24px rgba(0,0,0,0.3);
}

.service-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 1rem;
}

.service-info h3 {
    font-size: 1rem;
    font-weight: 600;
    margin-bottom: 0.25rem;
}

.service-info .description {
    font-size: 0.8rem;
    color: var(--text-secondary);
}

.service-status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.75rem;
    font-weight: 500;
    padding: 0.25rem 0.75rem;
    border-radius: 9999px;
    background: var(--bg-tertiary);
}

.service-status.healthy { background: rgba(63,185,80,0.15); color: var(--success); }
.service-status.unhealthy { background: rgba(248,81,73,0.15); color: var(--error); }
.service-status.warning { background: rgba(210,153,34,0.15); color: var(--warning); }
.service-status.unknown { background: rgba(139,148,158,0.15); color: var(--text-secondary); }

.service-status::before {
    content: '';
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
}

.service-details {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 0.75rem;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid var(--border);
}

.detail-item {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
}

.detail-label {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--text-secondary);
}

.detail-value {
    font-size: 0.875rem;
    font-family: monospace;
    color: var(--text-primary);
}

.detail-value a {
    color: var(--accent);
    text-decoration: none;
}

.detail-value a:hover { text-decoration: underline; }

.service-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid var(--border);
}

.btn {
    display: inline-flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.5rem 1rem;
    font-size: 0.8rem;
    font-weight: 500;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--bg-tertiary);
    color: var(--text-primary);
    cursor: pointer;
    transition: all 0.15s;
    text-decoration: none;
}

.btn:hover {
    border-color: var(--accent);
    background: var(--bg-secondary);
}

.btn.primary {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
}

.btn.primary:hover {
    background: var(--accent-hover);
    border-color: var(--accent-hover);
}

.btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.footer {
    padding: 1.5rem 2rem;
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.8rem;
    border-top: 1px solid var(--border);
    background: var(--bg-secondary);
}

.footer a { color: var(--accent); text-decoration: none; }
.footer a:hover { text-decoration: underline; }

/* Loading state */
.loading {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 3rem;
    color: var(--text-secondary);
}

.spinner {
    width: 24px;
    height: 24px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    margin-right: 1rem;
}

@keyframes spin { to { transform: rotate(360deg); } }

/* Empty state */
.empty-state {
    grid-column: 1 / -1;
    text-align: center;
    padding: 3rem;
    color: var(--text-secondary);
}

/* Responsive */
@media (max-width: 768px) {
    .header { flex-direction: column; gap: 1rem; text-align: center; }
    .system-info { flex-wrap: wrap; justify-content: center; }
    .main { padding: 1rem; }
    .stats-bar { grid-template-columns: 1fr 1fr; }
}
CSS_EOF

    # JavaScript
    cat > "$DASHBOARD_STATIC_DIR/js/dashboard.js" << 'JS_EOF'
const Dashboard = (() => {
    let config = { apiBase: '/api', refreshInterval: 30000 };
    let refreshTimer = null;
    
    async function api(path) {
        const res = await fetch(`${config.apiBase}${path}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
    }
    
    function renderServices(services) {
        const grid = document.getElementById('services-grid');
        if (!grid) return;
        
        if (!services || Object.keys(services).length === 0) {
            grid.innerHTML = '<div class="empty-state">No services configured</div>';
            return;
        }
        
        grid.innerHTML = Object.entries(services).map(([name, svc]) => `
            <div class="service-card ${svc.status || 'unknown'}">
                <div class="service-header">
                    <div class="service-info">
                        <h3>${formatName(name)}</h3>
                        <div class="description">${svc.description || 'No description'}</div>
                    </div>
                    <span class="service-status ${svc.status || 'unknown'}">${capitalize(svc.status || 'unknown')}</span>
                </div>
                <div class="service-details">
                    ${renderDetails(name, svc)}
                </div>
                <div class="service-actions">
                    ${renderActions(name, svc)}
                </div>
            </div>
        `).join('');
    }
    
    function formatName(name) {
        return name
            .replace(/_/g, ' ')
            .replace(/\b\w/g, c => c.toUpperCase())
            .replace(/Vpn /g, 'VPN ')
            .replace(/Ssl/g, 'SSL')
            .replace(/Api/g, 'API')
            .replace(/Ui/g, 'UI');
    }
    
    function capitalize(str) {
        return str.charAt(0).toUpperCase() + str.slice(1);
    }
    
    function renderDetails(name, svc) {
        const details = [];
        
        if (svc.port) details.push({ label: 'Port', value: svc.port });
        if (svc.url) details.push({ label: 'URL', value: `<a href="${svc.url}" target="_blank">${svc.url}</a>` });
        if (svc.version) details.push({ label: 'Version', value: svc.version });
        if (svc.models) details.push({ label: 'Models', value: svc.models });
        if (svc.containers) details.push({ label: 'Containers', value: svc.containers });
        if (svc.dashboards) details.push({ label: 'Dashboards', value: svc.dashboards });
        if (svc.uptime) details.push({ label: 'Uptime', value: svc.uptime });
        if (svc.memory) details.push({ label: 'Memory', value: svc.memory });
        if (svc.cpu) details.push({ label: 'CPU', value: svc.cpu });
        
        return details.map(d => `
            <div class="detail-item">
                <span class="detail-label">${d.label}</span>
                <span class="detail-value">${d.value}</span>
            </div>
        `).join('');
    }
    
    function renderActions(name, svc) {
        const actions = [];
        
        if (svc.url) {
            actions.push(`<a href="${svc.url}" target="_blank" class="btn primary">Open</a>`);
        }
        
        if (svc.status === 'unhealthy') {
            actions.push(`<button class="btn" onclick="restartService('${name}')" disabled>Restart</button>`);
        }
        
        actions.push(`<button class="btn" onclick="viewLogs('${name}')" disabled>Logs</button>`);
        
        return actions.join('');
    }
    
    function renderStats(services) {
        const bar = document.getElementById('stats-bar');
        if (!bar) return;
        
        const total = Object.keys(services).length;
        const healthy = Object.values(services).filter(s => s.status === 'healthy').length;
        const unhealthy = Object.values(services).filter(s => s.status === 'unhealthy').length;
        const warning = Object.values(services).filter(s => s.status === 'warning').length;
        const unknown = Object.values(services).filter(s => s.status === 'unknown').length;
        
        bar.innerHTML = `
            <div class="stat-card">
                <div class="label">Total Services</div>
                <div class="value">${total}</div>
            </div>
            <div class="stat-card">
                <div class="label">Healthy</div>
                <div class="value healthy">${healthy}</div>
            </div>
            <div class="stat-card">
                <div class="label">Unhealthy</div>
                <div class="value unhealthy">${unhealthy}</div>
            </div>
            <div class="stat-card">
                <div class="label">Warning</div>
                <div class="value warning">${warning}</div>
            </div>
            <div class="stat-card">
                <div class="label">Unknown</div>
                <div class="value">${unknown}</div>
            </div>
        `;
    }
    
    function updateSystemInfo(data) {
        document.getElementById('hostname').textContent = data.hostname || 'Unknown';
        document.getElementById('uptime').textContent = `Uptime: ${data.uptime || 'Unknown'}`;
        document.getElementById('last-updated').textContent = `Updated: ${new Date().toLocaleTimeString()}`;
        document.getElementById('version').textContent = data.version || '-';
    }
    
    async function refresh() {
        try {
            const [services, system] = await Promise.all([
                api('/services'),
                api('/system')
            ]);
            
            renderServices(services);
            renderStats(services);
            updateSystemInfo(system);
        } catch (err) {
            console.error('Dashboard refresh failed:', err);
            document.getElementById('services-grid').innerHTML = 
                '<div class="empty-state">Failed to load services</div>';
        }
    }
    
    function startAutoRefresh() {
        if (refreshTimer) clearInterval(refreshTimer);
        refreshTimer = setInterval(refresh, config.refreshInterval);
    }
    
    function stopAutoRefresh() {
        if (refreshTimer) clearInterval(refreshTimer);
        refreshTimer = null;
    }
    
    return {
        init(options) {
            config = { ...config, ...options };
            refresh();
            startAutoRefresh();
            
            // Refresh on visibility change
            document.addEventListener('visibilitychange', () => {
                if (!document.hidden) refresh();
            });
        },
        refresh,
        stop: stopAutoRefresh
    };
})();

// Global functions for buttons
window.restartService = (name) => {
    alert(`Restart ${name} - Not implemented yet`);
};

window.viewLogs = (name) => {
    alert(`View logs for ${name} - Not implemented yet`);
};
JS_EOF
}

# Create Python dashboard server
dashboard_create_server() {
    cat > "$DASHBOARD_DIR/server.py" << 'PY_EOF'
#!/usr/bin/env python3
"""
InitOps-Server Dashboard API Server
Lightweight HTTP server for service dashboard and API
"""

import json
import os
import subprocess
import sys
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import threading

DASHBOARD_DIR = Path("/opt/initops-dashboard")
TEMPLATES_DIR = DASHBOARD_DIR / "templates"
STATIC_DIR = DASHBOARD_DIR / "static"
STATE_FILE = Path("/home/vsp/Documents/sanjai's proj/InitOps-Server/state/.initops-state")
CONFIG_FILE = Path("/home/vsp/Documents/sanjai's proj/InitOps-Server/config/default.yaml")

class DashboardHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)
    
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        # API endpoints
        if path == '/api/health':
            self.send_json({"status": "healthy", "timestamp": time.time()})
        elif path == '/api/system':
            self.send_json(self.get_system_info())
        elif path == '/api/services':
            self.send_json(self.get_services())
        elif path == '/api/services/health':
            self.send_json(self.get_services_health())
        elif path.startswith('/api/service/'):
            service_name = path.split('/')[-1]
            self.send_json(self.get_service_detail(service_name))
        elif path == '/api/backup/list':
            self.send_json(self.get_backups())
        # Static files
        elif path.startswith('/static/'):
            self.serve_static(path[1:])  # Remove leading /
        # Dashboard UI
        elif path == '/' or path == '/dashboard':
            self.serve_template('index.html')
        else:
            self.send_error(404)
    
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        if path == '/api/service/restart':
            content_length = int(self.headers['Content-Length'])
            data = json.loads(self.rfile.read(content_length))
            service = data.get('service')
            result = self.restart_service(service)
            self.send_json(result)
        elif path == '/api/backup/create':
            result = self.create_backup()
            self.send_json(result)
        else:
            self.send_error(404)
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    
    def serve_template(self, name):
        try:
            content = (TEMPLATES_DIR / name).read_text()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(content.encode())
        except FileNotFoundError:
            self.send_error(404)
    
    def serve_static(self, path):
        try:
            file_path = STATIC_DIR / path
            if file_path.is_file():
                self.send_response(200)
                if path.endswith('.css'):
                    self.send_header('Content-Type', 'text/css')
                elif path.endswith('.js'):
                    self.send_header('Content-Type', 'application/javascript')
                self.end_headers()
                self.wfile.write(file_path.read_bytes())
            else:
                self.send_error(404)
        except Exception:
            self.send_error(404)
    
    def get_system_info(self):
        try:
            hostname = subprocess.check_output(['hostname'], text=True).strip()
            uptime = subprocess.check_output(['uptime', '-p'], text=True).strip()
            version = "1.0.0-alpha"
            try:
                with open("/home/vsp/Documents/sanjai's proj/InitOps-Server/initops.sh") as f:
                    for line in f:
                        if 'VERSION=' in line:
                            version = line.split('=')[1].strip().strip('"')
                            break
            except:
                pass
            
            return {
                "hostname": hostname,
                "uptime": uptime,
                "version": version,
                "timestamp": time.time()
            }
        except:
            return {"hostname": "unknown", "uptime": "unknown", "version": "unknown"}
    
    def get_services(self):
        """Get all services with status and metadata"""
        services = {}
        
        # Define service metadata
        service_meta = {
            'docker': {'description': 'Docker Engine', 'port': '2375,2376', 'type': 'native'},
            'ollama': {'description': 'Ollama LLM Server', 'port': '11434', 'url': 'http://localhost:11434', 'type': 'docker'},
            'nginx': {'description': 'Nginx Reverse Proxy', 'port': '80,443', 'url': 'https://localhost', 'type': 'native'},
            'raspap': {'description': 'RaspAP Wireless AP', 'port': '80,53,67', 'type': 'native'},
            'pihole': {'description': 'Pi-hole DNS/Ad-blocking', 'port': '53,8080,443', 'url': 'http://localhost:8080/admin', 'type': 'docker'},
            'n8n': {'description': 'n8n Workflow Automation', 'port': '5678', 'url': 'http://localhost:5678', 'type': 'docker'},
            'samba': {'description': 'Samba File Sharing', 'port': '139,445', 'type': 'native'},
            'sterling_pdf': {'description': 'Sterling PDF Toolkit', 'port': '3001', 'url': 'http://localhost:3001', 'type': 'docker'},
            'cockpit': {'description': 'Cockpit System Admin', 'port': '9090', 'url': 'https://localhost:9090', 'type': 'native'},
            'grafana': {'description': 'Grafana Dashboards', 'port': '3000', 'url': 'http://localhost:3000', 'type': 'docker'},
            'prometheus_stack': {'description': 'Prometheus Monitoring', 'port': '9090,9100,8080,9093', 'url': 'http://localhost:9090', 'type': 'docker'},
        }
        
        for name, meta in service_meta.items():
            status = self.check_service_health(name)
            service_info = {**meta, 'name': name, 'status': status}
            
            # Add dynamic details
            if name == 'ollama' and status == 'healthy':
                service_info['models'] = self.get_ollama_models()
            if name == 'docker' and status == 'healthy':
                service_info['containers'] = self.get_docker_containers()
            if name == 'grafana' and status == 'healthy':
                service_info['dashboards'] = self.get_grafana_dashboards()
            
            services[name] = service_info
        
        return services
    
    def get_services_health(self):
        services = self.get_services()
        return {name: svc.get('status', 'unknown') for name, svc in services.items()}
    
    def get_service_detail(self, name):
        services = self.get_services()
        return services.get(name, {"error": "Service not found"})
    
    def check_service_health(self, name):
        try:
            if name == 'docker':
                return 'healthy' if subprocess.run(['docker', 'info'], capture_output=True).returncode == 0 else 'unhealthy'
            elif name == 'ollama':
                return 'healthy' if subprocess.run(['curl', '-sf', 'http://localhost:11434/api/version'], capture_output=True).returncode == 0 else 'unhealthy'
            elif name == 'nginx':
                return 'healthy' if subprocess.run(['systemctl', 'is-active', '--quiet', 'nginx'], capture_output=True).returncode == 0 else 'unhealthy'
            elif name == 'raspap':
                return 'healthy' if all(subprocess.run(['systemctl', 'is-active', '--quiet', s], capture_output=True).returncode == 0 for s in ['hostapd', 'dnsmasq', 'lighttpd']) else 'unhealthy'
            elif name in ['pihole', 'n8n', 'sterling_pdf', 'grafana', 'prometheus_stack']:
                container = name if name != 'prometheus_stack' else 'prometheus'
                return 'healthy' if subprocess.run(['docker', 'ps', '--filter', f'name={container}', '--filter', 'status=running', '--format', '{{.Names}}'], capture_output=True, text=True).stdout.strip() == container else 'unhealthy'
            elif name == 'samba':
                return 'healthy' if all(subprocess.run(['systemctl', 'is-active', '--quiet', s], capture_output=True).returncode == 0 for s in ['smbd', 'nmbd']) else 'unhealthy'
            elif name == 'cockpit':
                return 'healthy' if subprocess.run(['systemctl', 'is-active', '--quiet', 'cockpit.socket'], capture_output=True).returncode == 0 else 'unhealthy'
        except:
            pass
        return 'unknown'
    
    def get_ollama_models(self):
        try:
            result = subprocess.run(['ollama', 'list'], capture_output=True, text=True)
            lines = result.stdout.strip().split('\n')
            return max(0, len(lines) - 1) if lines else 0
        except:
            return 0
    
    def get_docker_containers(self):
        try:
            result = subprocess.run(['docker', 'info', '--format', '{{.ContainersRunning}}/{{.Containers}}'], capture_output=True, text=True)
            return result.stdout.strip()
        except:
            return "0/0"
    
    def get_grafana_dashboards(self):
        try:
            result = subprocess.run(['curl', '-sf', 'http://localhost:3000/api/search'], capture_output=True, text=True)
            data = json.loads(result.stdout)
            return len(data)
        except:
            return 0
    
    def get_backups(self):
        backup_root = Path("/opt/backups/initops")
        backups = []
        if backup_root.exists():
            for item in backup_root.iterdir():
                stat = item.stat()
                backups.append({
                    "name": item.name,
                    "path": str(item),
                    "size": stat.st_size,
                    "modified": stat.st_mtime,
                    "type": "file" if item.is_file() else "directory"
                })
        return backups
    
    def restart_service(self, service):
        # Placeholder - would need proper implementation with sudo
        return {"success": False, "message": "Restart not implemented via API"}
    
    def create_backup(self):
        # Placeholder
        return {"success": False, "message": "Backup not implemented via API"}
    
    def log_message(self, format, *args):
        # Suppress default log messages
        pass

def run_server(port=8081):
    os.chdir(DASHBOARD_DIR)
    server = HTTPServer(('0.0.0.0', port), DashboardHandler)
    print(f"Dashboard server starting on http://0.0.0.0:{port}")
    print(f"API available at http://0.0.0.0:{port}/api")
    server.serve_forever()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    run_server(port)
PY_EOF
    chmod +x "$DASHBOARD_DIR/server.py"
}

# Create systemd service for dashboard
dashboard_create_service() {
    cat > /etc/systemd/system/initops-dashboard.service << EOF
[Unit]
Description=InitOps-Server Dashboard
After=network.target nginx.service
Wants=nginx.service

[Service]
Type=simple
User=root
WorkingDirectory=$DASHBOARD_DIR
ExecStart=/usr/bin/python3 $DASHBOARD_DIR/server.py $DASHBOARD_PORT
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Install dashboard
dashboard_install() {
    log_info "Installing InitOps-Server Dashboard..."
    
    # Install Python dependencies
    apt update && DEBIAN_FRONTEND=noninteractive apt install -y python3 python3-venv
    
    # Create dashboard files
    dashboard_create_template
    dashboard_create_server
    
    # Create systemd service
    dashboard_create_service
    
    # Enable and start
    systemctl daemon-reload
    systemctl enable --now initops-dashboard
    
    # Configure nginx to proxy dashboard
    dashboard_configure_nginx
    
    log_success "Dashboard installed"
    log_info "Access at: https://$(get_primary_ip)/dashboard"
}

dashboard_configure_nginx() {
    # Add dashboard location to nginx config
    local config_file="/etc/nginx/sites-available/initops"
    
    # Check if dashboard location already exists
    if grep -q "location /dashboard" "$config_file" 2>/dev/null; then
        return 0
    fi
    
    # Insert dashboard location before the closing brace of the main server block
    sed -i '/^    # Health check endpoint/i\
    # Dashboard\n    location /dashboard/ {\n        proxy_pass http://localhost:8081/;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n        proxy_http_version 1.1;\n        proxy_set_header Upgrade $http_upgrade;\n        proxy_set_header Connection "upgrade";\n    }\n' "$config_file"
    
    # Also add API proxy
    sed -i '/^    # Health check endpoint/i\
    # Dashboard API\n    location /api/ {\n        proxy_pass http://localhost:8081/;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n' "$config_file"
    
    nginx -t && systemctl reload nginx
}

# Service discovery - generate JSON for external tools
service_discovery_generate() {
    local output="${1:-/opt/initops-discovery.json}"
    local services
    services=$(health_get_status_json)
    
    cat > "$output" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "version": "${VERSION:-unknown}",
    "primary_ip": "$(get_primary_ip)",
    "services": $services
}
EOF
    
    log_info "Service discovery written to $output"
}

# Generate Traefik-compatible dynamic configuration
service_discovery_traefik() {
    local output="${1:-/opt/initops-traefik.yaml}"
    
    cat > "$output" << 'EOF'
# Traefik dynamic configuration for InitOps-Server services
# Generated by service_discovery_traefik()

http:
  routers:
    dashboard:
      rule: "PathPrefix(`/dashboard`)"
      service: dashboard
      middlewares:
        - auth-basic
      tls: {}
    
    api:
      rule: "PathPrefix(`/api`)"
      service: api
      tls: {}

  services:
    dashboard:
      loadBalancer:
        servers:
          - url: "http://localhost:8081"
        passHostHeader: true
    
    api:
      loadBalancer:
        servers:
          - url: "http://localhost:8081"
        passHostHeader: true

  middlewares:
    auth-basic:
      basicAuth:
        usersFile: "/etc/nginx/.htpasswd"
        removeHeader: true
EOF
    
    log_info "Traefik configuration written to $output"
}

# Generate Docker Compose labels for service discovery
service_discovery_docker_labels() {
    local service="$1"
    local labels=()
    
    case "$service" in
        ollama)
            labels=(
                "traefik.enable=true"
                "traefik.http.routers.ollama.rule=PathPrefix(\"/ollama\")"
                "traefik.http.routers.ollama.tls=true"
                "traefik.http.services.ollama.loadbalancer.server.port=11434"
            )
            ;;
        n8n)
            labels=(
                "traefik.enable=true"
                "traefik.http.routers.n8n.rule=PathPrefix(\"/n8n\")"
                "traefik.http.routers.n8n.tls=true"
                "traefik.http.services.n8n.loadbalancer.server.port=5678"
            )
            ;;
        grafana)
            labels=(
                "traefik.enable=true"
                "traefik.http.routers.grafana.rule=PathPrefix(\"/grafana\")"
                "traefik.http.routers.grafana.tls=true"
                "traefik.http.services.grafana.loadbalancer.server.port=3000"
            )
            ;;
        pihole)
            labels=(
                "traefik.enable=true"
                "traefik.http.routers.pihole.rule=PathPrefix(\"/pihole\")"
                "traefik.http.routers.pihole.tls=true"
                "traefik.http.services.pihole.loadbalancer.server.port=8080"
            )
            ;;
        sterling_pdf)
            labels=(
                "traefik.enable=true"
                "traefik.http.routers.sterling-pdf.rule=PathPrefix(\"/pdf\")"
                "traefik.http.routers.sterling-pdf.tls=true"
                "traefik.http.services.sterling-pdf.loadbalancer.server.port=3001"
            )
            ;;
    esac
    
    printf '%s\n' "${labels[@]}"
}