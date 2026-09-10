# Troubleshooting Guide

## Common Issues

### Script fails with "must be run as root"
**Cause**: Installation requires root privileges.
**Solution**: Run with `sudo ./initops.sh`

### OS compatibility check fails
**Cause**: Running on non-Debian-based system.
**Solution**: Use `--skip-os-check` flag for dry-run from other distros:
```bash
./initops.sh --skip-os-check --dry-run --config config.yaml
```

### Docker permission denied
**Cause**: User not in docker group.
**Solution**: 
```bash
# Logout and login again, or:
newgrp docker
```

### Service not accessible via nginx
**Cause**: nginx configuration or upstream service down.
**Solution**:
```bash
# Check nginx status
systemctl status nginx

# Test nginx config
nginx -t

# Check upstream services
systemctl status docker
docker ps

# Check nginx logs
journalctl -u nginx -f
```

### Pi-hole admin password not working
**Cause**: Password not set or container not ready.
**Solution**:
```bash
# Check container logs
docker logs pihole

# Get password from state
cat state/.initops-state | grep pihole_password
```

### Ollama model pull fails
**Cause**: Insufficient RAM or network issues.
**Solution**:
```bash
# Check available RAM
free -h

# Manually pull smaller model
ollama pull llama3.2:3b

# Check Ollama logs
journalctl -u ollama -f
```

### Samba shares not accessible
**Cause**: Firewall or configuration issues.
**Solution**:
```bash
# Check Samba status
systemctl status smbd nmbd

# Test config
testparm

# Check firewall
ufw status

# Check Samba logs
journalctl -u smbd -f
```

### Sterling PDF not loading
**Cause**: Container not ready or port conflict.
**Solution**:
```bash
# Check container
docker logs sterling-pdf

# Check port
ss -tuln | grep 3001

# Restart container
docker restart sterling-pdf
```

### Grafana login fails
**Cause**: Wrong password or container not initialized.
**Solution**:
```bash
# Get password from state
cat state/.initops-state | grep grafana_admin_password

# Check container logs
docker logs grafana

# Reset password (requires container restart)
docker exec grafana grafana-cli admin reset-admin-password newpassword
```

### n8n encryption key error
**Cause**: Key mismatch after restore.
**Solution**:
```bash
# Check state for encryption key
cat state/.initops-state | grep n8n_encryption_key

# Set in environment before starting
export N8N_ENCRYPTION_KEY=<key-from-state>
```

## Debug Mode

Enable debug logging:
```bash
DEBUG=true ./initops.sh
```

## Dry Run Mode

Test without making changes:
```bash
./initops.sh --dry-run --config config.yaml
```

## Reset Installation State

To force re-installation of a module:
```bash
# Remove specific state
sed -i '/^ollama=/d' state/.initops-state

# Or reset all state
./initops.sh --reset-state
```

## Log Locations

| Component | Log Location |
|-----------|--------------|
| System | `journalctl -u <service>` |
| Docker containers | `docker logs <container>` |
| nginx | `/var/log/nginx/` |
| Samba | `/var/log/samba/` |
| State file | `state/.initops-state` |

## Getting Help

1. Check [GitHub Issues](https://github.com/SanjaiPS-tech/IntiOps-Server/issues)
2. Search [GitHub Discussions](https://github.com/SanjaiPS-tech/IntiOps-Server/discussions)
3. Run with `DEBUG=true` and share output
4. Include `state/.initops-state` (sanitized) in bug reports