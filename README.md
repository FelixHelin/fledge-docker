# Fledge Docker

This repository contains a Docker setup for running Fledge IoT Platform with PostgreSQL database, built from source. The setup includes both the Fledge core service and a web-based UI made by [Rob Raesemann](https://github.com/RobRaesemann).

## Important Caveat

When building ARM-based Docker images on an AMD64 host (e.g., building a Raspberry Pi-compatible container from your laptop), ensure that QEMU emulation is enabled. Without this, the build will fail with an error such as:

```
exec /bin/sh: exec format error
```

To enable QEMU emulation, run:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p
```

## Overview
 This Docker setup includes:

- Fledge core service (version 3.0.0)
- PostgreSQL database (version 13)
- Fledge GUI
- Various Fledge plugins and filters
- Log rotation configuration

## Prerequisites

- Docker

## Architecture

The setup consists of two main containers:

1. **fledge-86**: Main Fledge service container
   - Built from source
   - Includes PostgreSQL database
   - Exposes port 8081 for Fledge API
   - Includes various plugins and filters
   - Runs cron service for log rotation

2. **fledge-ui**: Web-based user interface
   - Based on `robraesemann/fledge-gui:latest`
   - Exposes port 8001 for web access

## Getting Started
. Build and start the containers:
   ```bash
   docker-compose up -d
   ```

3. Access the services:
   - Fledge API: http://localhost:8081
   - Fledge UI: http://localhost:8001

## Included Fledge Components

### Filters
- Delta
- Asset
- Change
- Metadata
- Python35
- Rate
- Threshold
- OMF Hint

### North Plugins
- HTTPC
- HTTP North

### South Plugins
- Modbus TCP
- Sinusoid
- HTTP South
- Modbus
- MQTT Readings
- S2OPCUA

## Configuration

### Logging
- System logs are managed by rsyslog
- Log rotation is configured to:
  - Rotate weekly
  - Keep 5 rotations
  - Compress old logs
  - Maximum size: 1MB
  
- **Cron Service**: The cron service is started specifically to ensure proper log rotation functionality.