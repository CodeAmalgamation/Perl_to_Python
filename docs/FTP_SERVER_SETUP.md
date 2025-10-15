# FTP Server Setup for Testing

This guide provides step-by-step instructions to set up a local FTP server using Docker for testing the FTP implementation.

## Prerequisites

- Docker installed and running
- Terminal/command line access

## Quick Setup

### 1. Pull the Docker Image

```bash
docker pull delfer/alpine-ftp-server
```

**Note**: We use `delfer/alpine-ftp-server` instead of `fauria/vsftpd` because it's ARM64-compatible (works on Apple Silicon Macs).

### 2. Create Local FTP Directory

```bash
mkdir -p /tmp/ftp_test
chmod 777 /tmp/ftp_test
```

This directory will be mounted as the FTP user's home directory, allowing file uploads and downloads.

### 3. Start the FTP Server Container

```bash
docker run -d \
  --name test_ftp \
  -p 21:21 \
  -p 21000-21010:21000-21010 \
  -e USERS="ftptest|ftptest123|/ftp/ftptest|1000" \
  -e ADDRESS=localhost \
  -e MIN_PORT=21000 \
  -e MAX_PORT=21010 \
  -e WRITE_ENABLE=YES \
  -v /tmp/ftp_test:/ftp/ftptest \
  delfer/alpine-ftp-server
```

**Configuration Details**:
- `--name test_ftp` - Container name
- `-p 21:21` - FTP control port
- `-p 21000-21010:21000-21010` - Passive mode data ports
- `-e USERS="ftptest|ftptest123|/ftp/ftptest|1000"` - Username|Password|HomeDir|UID
- `-e ADDRESS=localhost` - Server address for passive mode
- `-e WRITE_ENABLE=YES` - Enable file uploads
- `-v /tmp/ftp_test:/ftp/ftptest` - Mount local directory

### 4. Verify Container is Running

```bash
docker ps | grep test_ftp
```

You should see output showing the container is running.

### 5. Set Directory Permissions Inside Container

```bash
docker exec test_ftp chmod 777 /ftp/ftptest
```

## FTP Server Credentials

- **Host**: `127.0.0.1` or `localhost`
- **Username**: `ftptest`
- **Password**: `ftptest123`
- **Port**: `21`
- **Home Directory**: `/ftp/ftptest` (mapped to `/tmp/ftp_test` on host)

## Testing the FTP Server

### Option 1: Run Production Test Suite

```bash
cd /Users/shubhamdixit/Perl_to_Python
perl Test_Scripts/test_ftp_production.pl
```

Expected result: 68/68 tests passing (100%)

### Option 2: Run Simple Login Test

```bash
cd /Users/shubhamdixit/Perl_to_Python
perl Test_Scripts/test_ftp_simple_login.pl
```

This interactive test demonstrates file upload, download, and delete operations.

### Option 3: Test with Command Line FTP Client

```bash
ftp localhost
# Username: ftptest
# Password: ftptest123
# Commands: ls, pwd, get, put, delete, quit
```

### Option 4: Test with Python

```python
from ftplib import FTP

ftp = FTP('localhost')
ftp.login('ftptest', 'ftptest123')
print(ftp.pwd())
print(ftp.nlst())
ftp.quit()
```

## Managing the FTP Server

### Stop the FTP Server

```bash
docker stop test_ftp
```

### Start the FTP Server (if stopped)

```bash
docker start test_ftp
```

### View FTP Server Logs

```bash
docker logs test_ftp
```

### Remove the FTP Server Container

```bash
docker stop test_ftp
docker rm test_ftp
```

### Access Files on Host System

Files uploaded to the FTP server are accessible at:
```bash
ls -la /tmp/ftp_test/
```

## Troubleshooting

### Connection Refused Error

**Problem**: Cannot connect to FTP server

**Solution**:
1. Check if container is running: `docker ps | grep test_ftp`
2. Check if port 21 is available: `lsof -i :21`
3. Restart container: `docker restart test_ftp`

### Permission Denied on Upload

**Problem**: "553 Could not create file" error

**Solution**:
1. Set host directory permissions: `chmod 777 /tmp/ftp_test`
2. Set container directory permissions: `docker exec test_ftp chmod 777 /ftp/ftptest`
3. Verify WRITE_ENABLE=YES is set in container environment

### Platform Compatibility Issues

**Problem**: Container crashes with segmentation fault

**Solution**: Use `delfer/alpine-ftp-server` instead of `fauria/vsftpd` - it's ARM64-compatible.

## Environment Variables

You can configure the test scripts using these environment variables:

```bash
export FTP_TEST_HOST='127.0.0.1'
export FTP_TEST_USER='ftptest'
export FTP_TEST_PASS='ftptest123'
```

## Notes

- The FTP server uses passive mode for data transfers (ports 21000-21010)
- Files are stored in `/tmp/ftp_test` on the host system
- The server automatically creates the home directory on first login
- All uploaded files persist even if the container is restarted
- Remove `/tmp/ftp_test` directory to clean up all test files
