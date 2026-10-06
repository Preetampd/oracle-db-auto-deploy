# oracle-db-auto-deploy
Automating Oracle 19c/23ai Deployments Stop Wasting Time on Manual Setups
# Oracle 23ai/19c Automated Deployment Script

An automated, bash-based provisioning script to rapidly deploy Oracle Database 23ai (or 19c) on Linux. This tool handles user creation, silent software installation, container database (CDB/PDB) creation, listener configuration, and systemd service registration.

**Note:** This script is designed for development, testing, and sandbox environments. It is not intended for production systems without supplementary OS hardening and prerequisite configuration.

## Features
* End-to-end silent installation
* Automatic systemd service creation for auto-start/stop
* Dynamic IP and environment configuration
* Secure password handling (prompts or secure environment variables)

## Prerequisites
1. **OS Requirements:** RHEL/Oracle Linux 8 or 9 (Run as `root`).
2. **Oracle Prerequisites:** Ensure Oracle pre-installation packages are installed (e.g., `oracle-database-preinstall-23ai`).
3. **Software:** The Oracle installation zip file (e.g., `LINUX.X64_2326100_db_home.zip`) must be present on the server.
4. **Dependencies:** `unzip` and `rlwrap` (optional, for sqlplus history).

## Installation & Usage

1. Clone this repository:
   ```bash
   git clone [https://github.com/Preetampd/oracle-db-auto-deploy.git](https://github.com/yourusername/oracle-db-auto-deploy.git)
   cd oracle-db-auto-deploy
   chmod +x deploy_oracle.sh
2. Run the script as root:
   ```bash
   sudo ./deploy_oracle.sh
  
You will be prompted to enter paths, IP addresses, and secure passwords. Alternatively, you can pre-set environment variables to bypass prompts for CI/CD pipelines.

Configuration Guidance:

Variables can be customized at the top of the script or passed as environment variables:

ORACLE_BASE:Base directory for Oracle (default: /u01/app/oracle)

ORACLE_HOME: Home directory (default: /u01/app/oracle/product/23.0.0/dbhome_1)

ZIP_SOURCE: Path to the Oracle installer zip.

LISTENER_IP: The IP bound to the Oracle Listener.

Security Considerations:

No Hardcoded Passwords: The script prompts for sensitive passwords at runtime.

Response Files: Temporary installation files containing sensitive data are securely deleted after use.

Production Warning: This script skips prerequisite checks (-ignorePrereqFailure). For production, ensure OS tuning (sysctl.conf, limits.conf) is managed via Ansible or Puppet.
   
