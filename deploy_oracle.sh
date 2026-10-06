```bash
#!/bin/bash
# ==============================================================================
# AUTOMATIC ORACLE 23ai DEPLOYMENT SCRIPT
# Validation: Sandbox / Development Infrastructure
# ==============================================================================

# --- 1. SET ENVIRONMENT VARIABLES ---
export ORACLE_BASE=${ORACLE_BASE:-/u01/app/oracle}
export ORACLE_HOME=${ORACLE_HOME:-$ORACLE_BASE/product/23.0.0/dbhome_1}
export INVENTORY=${INVENTORY:-/u01/app/oraInventory}
export ORACLE_SID=${ORACLE_SID:-orcl}
export ZIP_SOURCE=${ZIP_SOURCE:-/softwares/LINUX.X64_2326100_db_home.zip}

# Dynamically determine IP or allow user override
DEFAULT_IP=$(hostname -I | awk '{print $1}')
export LISTENER_IP=${LISTENER_IP:-$DEFAULT_IP}

# Ensure script is running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as the root user."
  exit 1
fi

# Ensure required packages exist
command -v unzip >/dev/null 2>&1 || { echo >&2 "ERROR: 'unzip' is required but not installed. Aborting."; exit 1; }

echo ">>> 0. Gathering Secure Credentials..."
if [ -z "$ORACLE_OS_PASSWORD" ]; then
    read -s -p "Enter password for OS user 'oracle': " ORACLE_OS_PASSWORD
    echo
fi
if [ -z "$DB_PASSWORD" ]; then
    read -s -p "Enter SYS/SYSTEM Database Password: " DB_PASSWORD
    echo
fi
if [ -z "$PDB_PASSWORD" ]; then
    read -s -p "Enter PDB Admin Password: " PDB_PASSWORD
    echo
fi

echo ">>> 1. Creating Oracle OS Groups and User..."
getent group oinstall >/dev/null || groupadd oinstall
getent group dba >/dev/null || groupadd dba

if ! id -u oracle >/dev/null 2>&1; then
    useradd -g oinstall -G dba -m -s /bin/bash oracle
    echo "Oracle user created successfully."
else
    usermod -g oinstall -G dba oracle
    echo "Oracle user already exists. Groups updated."
fi

# Securely set password
echo "oracle:$ORACLE_OS_PASSWORD" | chpasswd

echo ">>> 2. Configuring /u01 Directory Permissions..."
mkdir -p /u01
chown -R oracle:oinstall /u01
chmod -R 775 /u01

echo ">>> 3. Cleaning old paths and preparing Oracle Home..."
if [ -z "$ORACLE_HOME" ] || [ "$ORACLE_HOME" == "/" ]; then
    echo "ERROR: ORACLE_HOME is invalid or unsafe."
    exit 1
fi
su - oracle -c "rm -rf $ORACLE_HOME/*"
su - oracle -c "mkdir -p $ORACLE_HOME $INVENTORY"

echo ">>> 4. Extracting installation zip..."
if [ ! -f "$ZIP_SOURCE" ]; then
    echo "ERROR: Source file $ZIP_SOURCE not found!"
    exit 1
fi
unzip -q "$ZIP_SOURCE" -d "$ORACLE_HOME" || { echo "ERROR: Unzip failed."; exit 1; }
chown -R oracle:oinstall "$ORACLE_HOME"

echo ">>> 5. Generating the 23ai silent response file..."
cat << EOF > /tmp/db_install.rsp
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v23.0.0
oracle.install.option=INSTALL_DB_SWONLY
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=$INVENTORY
ORACLE_HOME=$ORACLE_HOME
ORACLE_BASE=$ORACLE_BASE
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=dba
oracle.install.db.OSBACKUPDBA_GROUP=dba
oracle.install.db.OSDGDBA_GROUP=dba
oracle.install.db.OSKMDBA_GROUP=dba
oracle.install.db.OSRACDBA_GROUP=dba
oracle.install.db.rootconfig.executeRootScript=false
EOF
chown oracle:oinstall /tmp/db_install.rsp

echo ">>> 6. Running silent software installer..."
su - oracle -c "cd $ORACLE_HOME && ./runInstaller -silent -responseFile /tmp/db_install.rsp -ignorePrereqFailure" || { echo "ERROR: runInstaller failed."; exit 1; }

# Securely remove response file
rm -f /tmp/db_install.rsp

echo ">>> 7. Executing Post-Installation Root Scripts..."
[ -f "$INVENTORY/orainstRoot.sh" ] && $INVENTORY/orainstRoot.sh
$ORACLE_HOME/root.sh

echo ">>> 8. Creating Container & Pluggable Database..."
su - oracle -c "
$ORACLE_HOME/bin/dbca -silent -createDatabase \
  -gdbName $ORACLE_SID \
  -sid $ORACLE_SID \
  -createAsContainerDatabase true \
  -numberOfPDBs 1 \
  -pdbName pdb1 \
  -templateName $ORACLE_HOME/assistants/dbca/templates/General_Purpose.dbc \
  -sysPassword '$DB_PASSWORD' \
  -systemPassword '$DB_PASSWORD' \
  -pdbAdminPassword '$PDB_PASSWORD' \
  -datafileDestination $ORACLE_BASE/oradata \
  -storageType FS \
  -characterSet AL32UTF8 \
  -totalMemory 2048
" || { echo "ERROR: DBCA Database creation failed."; exit 1; }

echo ">>> 9. Configuring and Starting Listener L1..."
su - oracle -c "mkdir -p $ORACLE_HOME/network/admin"
cat << EOF > $ORACLE_HOME/network/admin/listener.ora
SID_LIST_L1 =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = pdb1)
      (ORACLE_HOME = $ORACLE_HOME)
      (SID_NAME = $ORACLE_SID)
    )
  )

L1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $LISTENER_IP)(PORT = 1521))
  )

ADR_BASE_L1 = $ORACLE_BASE
EOF
chown oracle:oinstall $ORACLE_HOME/network/admin/listener.ora

su - oracle -c "export ORACLE_HOME=$ORACLE_HOME
export ORACLE_BASE=$ORACLE_BASE
export PATH=$ORACLE_HOME/bin:\$PATH
\$ORACLE_HOME/bin/lsnrctl start L1"

echo ">>> 10. Configuring Auto-Startup /etc/oratab..."
sed -i "s/^${ORACLE_SID}:${ORACLE_HOME//\//\\\/}:N/${ORACLE_SID}:${ORACLE_HOME//\//\\\/}:Y/g" /etc/oratab
if ! grep -q "^${ORACLE_SID}:${ORACLE_HOME}:Y" /etc/oratab; then
    echo "${ORACLE_SID}:${ORACLE_HOME}:Y" >> /etc/oratab
fi

echo ">>> 11. Deploying Systemd Service..."
cat << EOF > /etc/systemd/system/oracle-db.service
[Unit]
Description=Oracle Database and Listener Service
After=syslog.target network.target local-fs.target remote-fs.target

[Service]
Type=forking
RemainAfterExit=yes
User=oracle
Group=oinstall
Environment=ORACLE_HOME=$ORACLE_HOME

ExecStart=/bin/bash -c '${ORACLE_HOME}/bin/dbstart ${ORACLE_HOME}'
ExecStop=/bin/bash -c '${ORACLE_HOME}/bin/dbshut ${ORACLE_HOME}'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable oracle-db.service

echo ">>> 12. Appending shortcuts to .bash_profile..."
sed -i '/Oracle Environment Settings/,$d' /home/oracle/.bash_profile 2>/dev/null

cat << EOF >> /home/oracle/.bash_profile

# --- Oracle Environment Settings ---
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$PATH:\$ORACLE_HOME/bin
alias sp='sqlplus / as sysdba'
alias sqlplus='rlwrap sqlplus'
alias rman='rlwrap rman'
EOF
chown oracle:oinstall /home/oracle/.bash_profile

echo ">>> 13. Verifying Database Status..."
su - oracle -c "
$ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
SET PAGESIZE 40 FEEDBACK OFF VERIFY OFF
SELECT 'CDB Status is: ' || status FROM v\\\$instance;
SHOW PDBS;
EXIT;
EOF
"

echo ">>> SUCCESS! Setup completed."
