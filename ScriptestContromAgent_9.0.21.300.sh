#Installation Java==================================================
#!/bin/ksh
# ==================================================================
# Script : ensure_java_controlm.ksh
# Purpose : Ensure / Install Java 11 required by Control-M Agent
#           version 9.0.21.300 on AIX and Linux (RHEL 7/8/9).
# ==================================================================

# ------------------------------------------------------------------
# Global variable: expected Java version
# Control-M 9.0.21.300 requires Java 11 (BMC recommends Semeru/OpenJDK 11).
# ------------------------------------------------------------------
CTM_JAVA_VERSION=11

# ------------------------------------------------------------------
# Function log: print a message with timestamp (for debugging).
# ------------------------------------------------------------------
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# ------------------------------------------------------------------
# Function die: print an error and stop the script.
# ------------------------------------------------------------------
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# ------------------------------------------------------------------
# Function detect_os: detect the operating system (AIX or Linux).
# ------------------------------------------------------------------
detect_os() {
  OS_NAME="$(uname -s 2>/dev/null)"
  case "$OS_NAME" in
    Linux) echo "Linux";;
    AIX)   echo "AIX";;
    *)     die "Unsupported OS: ${OS_NAME:-unknown}";;
  esac
}

# ------------------------------------------------------------------
# Function install_java_linux:
# Install Java 11 on Linux Red Hat (via yum or dnf).
# Then determine automatically JAVA_HOME.
# ------------------------------------------------------------------
install_java_linux() {
  log "Linux detected → installing OpenJDK ${CTM_JAVA_VERSION}"

  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "java-${CTM_JAVA_VERSION}-openjdk" || \
    sudo dnf install -y "java-${CTM_JAVA_VERSION}-openjdk-headless"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "java-${CTM_JAVA_VERSION}-openjdk" || \
    sudo yum install -y "java-${CTM_JAVA_VERSION}-openjdk-headless"
  else
    die "Neither yum nor dnf found. Please install OpenJDK ${CTM_JAVA_VERSION} manually."
  fi

  # Automatically resolve JAVA_HOME from java binary
  JAVABIN="$(command -v java)"
  REALBIN="$(readlink -f "$JAVABIN" 2>/dev/null || echo "$JAVABIN")"
  export BMC_INST_JAVA_HOME="$(dirname "$(dirname "$REALBIN")")"
  log "Java installed at $BMC_INST_JAVA_HOME"
}

# ------------------------------------------------------------------
# Function install_java_aix:
# Check if Java 11 is present at /usr/java11_64.
# If not, try installation via installp from $AIX_JAVA_FILES_DIR
# (must point to an NFS/NIM directory with IBM Semeru images).
# ------------------------------------------------------------------
install_java_aix() {
  log "AIX detected → required Java is IBM Semeru 11 (64-bit)"

  if [ -x /usr/java11_64/bin/java ]; then
    export BMC_INST_JAVA_HOME="/usr/java11_64"
    log "Java 11 already present at $BMC_INST_JAVA_HOME"
    return
  fi

  if [ -n "${AIX_JAVA_FILES_DIR:-}" ] && [ -d "${AIX_JAVA_FILES_DIR}" ]; then
    log "Installing Java 11 from $AIX_JAVA_FILES_DIR ..."
    sudo installp -aY -d "${AIX_JAVA_FILES_DIR}" all || die "installp failed"
    [ -x /usr/java11_64/bin/java ] || die "Java 11 not found after installp"
    export BMC_INST_JAVA_HOME="/usr/java11_64"
    log "Java 11 installed at $BMC_INST_JAVA_HOME"
  else
    die "Java 11 not available. Set AIX_JAVA_FILES_DIR or install IBM Semeru manually."
  fi
}

# ------------------------------------------------------------------
# Function validate_java:
# Check that Java is present and its version is 11.x
# ------------------------------------------------------------------
validate_java() {
  [ -x "${BMC_INST_JAVA_HOME}/bin/java" ] || die "Java binary missing in $BMC_INST_JAVA_HOME"
  ver="$("${BMC_INST_JAVA_HOME}/bin/java" -version 2>&1 | head -1)"
  echo "$ver" | grep 'version "11\.' >/dev/null 2>&1 || die "Unsupported version ($ver). Java 11 required."
  log "Java validated: $ver"
}

# ------------------------------------------------------------------
# MAIN : main script execution
# ------------------------------------------------------------------
OS=$(detect_os)

case $OS in
  Linux) install_java_linux ;;
  AIX)   install_java_aix ;;
esac

validate_java

echo "BMC_INST_JAVA_HOME=${BMC_INST_JAVA_HOME}"

#===============================================================
# cat exploitcontrolm.ksh
#!/bin/ksh

###########################################################
# INFO : SCRIPT D'EXPLOITATION CONTROL-M
# POUR : CREDIT AGRICOLE
###########################################################
# 2025.03.09 : Adams N - Creation
# 2023 07 13 : Adams N - Update ProductVersion 9.0.21.300
###########################################################

# VARIABLE GLOBAL
###########################################################

export PATH=/bin:/usr/bin:/usr/sbin:/tools/admin/bin
ProductVersion="${CTM_VERSION:-9.0.21.300}"
Repository="/softwares/PRODUITS/CONTROLM"
OS=$1
OPT=$2
Envir=$3
OSuname=$(uname)
OSlevel=$(oslevel)

#- Fonctions -##############################################

function Envir
{
case $Envir in
              HP|PR) ;;
                  *) echo "Parametre Envir invalide : $4"
                     echo "Autorisation pour : HP|PR"
                     echo "Abandon..."
                     exit 1 ;;
esac
}

function nimmount
{
    echo "-> Montage du serveur NIM"

    /tools/admin/bin/mountnim
}

function nimunmount
{
    echo "-> Demontage du serveur NIM"

    /tools/admin/bin/umountnim
}

# GESTION AIX
###########################################################

function installaixstandalone
{

    echo "-> Installation Control-M Agent AIX vers ${ProductVersion} (standalone)"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    REPO_VER="${Repository}/V${ProductVersion}/AGENT"
    PARAM_XML="${REPO_VER}/agent_params.xml"
    if [ -x "${REPO_VER}/AIX/setup.sh" ] && [ -f "${PARAM_XML}" ]; then
        echo "-> Utilisation du média versionné: ${REPO_VER}"
        "${REPO_VER}/AIX/setup.sh" -silent "${PARAM_XML}" -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
    else
        echo "-> Média versionné introuvable, fallback vers wrapper legacy Install_Aix_CTMAGT.ksh"
        BMC_INST_JAVA_HOME="${BMC_INST_JAVA_HOME}" "${Repository}/AixInstall/Install_Aix_CTMAGT.ksh" -e "${Envir}"
    fi

}

function installaixclusteractif
{

    echo "-> Installation Control-M Agent AIX ${ProductVersion} (cluster ACTIF)"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    REPO_VER="${Repository}/V${ProductVersion}/AGENT"
    PARAM_XML="${REPO_VER}/agent_params.xml"
    if [ -x "${REPO_VER}/AIX/setup.sh" ] && [ -f "${PARAM_XML}" ]; then
        echo "-> Utilisation du média versionné: ${REPO_VER}"
        "${REPO_VER}/AIX/setup.sh" -silent "${PARAM_XML}" -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
        echo "-> Pensez à appliquer la config cluster (script post-install interne)"
    else
        echo "-> Média versionné introuvable, fallback vers wrapper legacy Install_Aix_CTMAGT_Cluster_ACTIF.ksh"
        BMC_INST_JAVA_HOME="${BMC_INST_JAVA_HOME}" "${Repository}/AixInstall/Install_Aix_CTMAGT_Cluster_ACTIF.ksh" -e "${Envir}"
    fi

}

function installaixclusterpassif
{

    echo "-> Installation Control-M Agent AIX ${ProductVersion} (cluster PASSIF)"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    REPO_VER="${Repository}/V${ProductVersion}/AGENT"
    PARAM_XML="${REPO_VER}/agent_params.xml"
    if [ -x "${REPO_VER}/AIX/setup.sh" ] && [ -f "${PARAM_XML}" ]; then
        echo "-> Utilisation du média versionné: ${REPO_VER}"
        "${REPO_VER}/AIX/setup.sh" -silent "${PARAM_XML}" -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
        echo "-> Pensez à appliquer la config cluster (script post-install interne)"
    else
        echo "-> Média versionné introuvable, fallback vers wrapper legacy Install_Aix_CTMAGT_Cluster_PASSIF.ksh"
        BMC_INST_JAVA_HOME="${BMC_INST_JAVA_HOME}" "${Repository}/AixInstall/Install_Aix_CTMAGT_Cluster_PASSIF.ksh" -e "${Envir}"
    fi

}

function upgradeagentaix
{
    echo "-> Upgrade Control-M Agent AIX vers ${ProductVersion}"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    cd /tools/list/ctmagent/ctmagt
    PARAM_XML="${Repository}/V${ProductVersion}/AGENT/agent_params.xml"
    ${Repository}/V${ProductVersion}/AGENT/AIX/setup.sh \
        -silent "${PARAM_XML}" \
        -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
}
function StartctmagtAix
{
    echo "-> Start Control-M Agent AIX"
    /tools/list/ctmagent/ctmagt/ctm/scripts/start-ag -u ctmagt -p all
    chmod 644 /tools/list/ctmagent/ctmagt/ctm/proclog/start_ag*
    chmod -R 755 /tools/list/ctmagent/ctmagt/ctm/proclog/LogsZip
    chmod -R 755 /tools/list/ctmagent/ctmagt/ctm/proclog/Metrics
}

function StopctmagtAix
{
    echo "-> Stop Control-M Agent AIX"
    /tools/list/ctmagent/ctmagt/ctm/scripts/shut-ag -u ctmagt -p all
}

function uninstallCTMAix
{
    echo "-> desinstallation de Control-M sur AIX"

    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    ${Repository}/AixInstall/CTMuninstall.ksh
}

# GESTION LINUX
###########################################################

function installlinuxstandalone
{

    echo "-> Installation Control-M Agent LINUX vers ${ProductVersion} (standalone)"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    REPO_VER="${Repository}/V${ProductVersion}/AGENT"
    PARAM_XML="${REPO_VER}/agent_params.xml"
    if [ -x "${REPO_VER}/Linux/setup.sh" ] && [ -f "${PARAM_XML}" ]; then
        echo "-> Utilisation du média versionné: ${REPO_VER}"
        "${REPO_VER}/Linux/setup.sh" -silent "${PARAM_XML}" -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
    else
        echo "-> Média versionné introuvable, fallback vers wrapper legacy Install_Linux_CTMAGT.ksh"
        BMC_INST_JAVA_HOME="${BMC_INST_JAVA_HOME}" "${Repository}/LinuxInstall/Install_Linux_CTMAGT.ksh" -e "${Envir}"
    fi

}

function upgradeagentlinux
{
    echo "-> Upgrade Control-M Agent LINUX vers ${ProductVersion}"
    ensure_java
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    cd /tools/list/ctmagent/ctmagt
    PARAM_XML="${Repository}/V${ProductVersion}/AGENT/agent_params.xml"
    ${Repository}/V${ProductVersion}/AGENT/Linux/setup.sh \
        -silent "${PARAM_XML}" \
        -BMC_INST_JAVA_HOME "${BMC_INST_JAVA_HOME}"
}

function uninstallCTMLinux
{
    echo "-> desinstallation de Control-M sur LINUX"
    export PATH=$PATH:$HOME/bin:/tools/admin/local/bin:/tools/admin/bin:/tools/admin/san:/usr/local/bin:/sbin
    ${Repository}/LinuxInstall/CTMuninstall.ksh
}

function StartctmagtLinux
{
   CheckSystemd=$(command -v systemctl >/dev/null 2>&1 && echo yes || echo no)
   if [[ ${CheckVersion} < 7 ]] ; then
    echo "-> Start Control-M Agent LINUX without use systemctl..."
    /tools/list/ctmagent/ctmagt/ctm/scripts/start-ag -u ctmagt -p all
   else
    echo "-> Start Control-M Agent LINUX with systemctl..."
    systemctl start ctmagent.service
   fi
   chmod 644 /tools/list/ctmagent/ctmagt/ctm/proclog/start_ag*
   chmod -R 755 /tools/list/ctmagent/ctmagt/ctm/proclog/LogsZip
   chmod -R 755 /tools/list/ctmagent/ctmagt/ctm/proclog/Metrics
}

function StopctmagtLinux
{
   CheckSystemd=$(command -v systemctl >/dev/null 2>&1 && echo yes || echo no)
   if [[ ${CheckVersion} < 7 ]] ; then
    echo "-> Stop Control-M Agent LINUX without use systemctl..."
    /tools/list/ctmagent/ctmagt/ctm/scripts/shut-ag -u ctmagt -p all
   else
    echo "-> Stop Control-M Agent LINUX with systemctl..."
    systemctl stop ctmagent.service
   fi
}

function StartctmemLinux
{
   echo "-> Start Control-M EM LINUX with systemctl..."
   systemctl start ctmem.service
}

function StopctmemLinux
{
   echo "-> Stop Control-M EM LINUX with systemctl..."
   systemctl stop ctmem.service
}

function StartctmserverLinux
{
   echo "-> Start Control-M Server LINUX with systemctl..."
   systemctl start ctmserver.service
}

function StopctmserverLinux
{
   echo "-> Stop Control-M Server LINUX with systemctl..."
   systemctl stop ctmserver.service
}

function StartctmcaLinux
{
   echo "-> Start Control-M Serverr-CA LINUX with systemctl..."
   systemctl start ctmca.service
}

function StopctmcaLinux
{
   echo "-> Stop Control-M Server-CA LINUX with systemctl..."
   systemctl stop ctmca.service
}

# AUTRE
###########################################################

function usage
{
    clear
    echo
    echo "Usage : exploitcontrolm.ksh [AIX]   [INSTALLSTANDALONE|INSTALLCLUSTERACTIF|INSTALLCLUSTERPASSIF] [HP|PR]"
    echo "                            [LINUX] [INSTALLSTANDALONE]                                          [HP|PR]"
    echo
    echo "                            [AIX]   [UPDGRADEAGENT]"
    echo "                            [LINUX] [UPDGRADEAGENT]"
    echo
    echo "                            [AIX]   [STARTCTMAGTAIX|STOPCTMAGTAIX]"
    echo "                            [LINUX] [STARTCTMAGTLINUX|STOPCTMAGTLINUX]"
    echo
    echo "                            [AIX]   [UNINSTALLCTMAIX]"
    echo "                            [LINUX] [UNINSTALLCTMLINUX]"
    echo
    echo "                            [LINUX] [STARTCTMEM|STOPCTMEM]"
    echo
    echo "                            [LINUX] [STARTCTMSERVER|STOPCTMSERVER]"
    echo "                            [LINUX] [STARTCTMCA|STOPCTMCA]"
    echo
    echo "                            [AUTRE] [MOUNTNIM|UMOUNTNIM"
}

case $OS in

    AIX)
        echo "OS         : ${OSuname}"
        echo "OS version : ${OSlevel}"
        echo ${OSuname} | grep -i AIX > /dev/null
        RC=${?}
        if [[ ${RC} != 0 ]] ; then
         echo "################################################"
         echo "ABORTED TOOLS :                                 "
         echo "Selected COMMAND is not for this OS : ${OSuname}"
         echo "################################################"
         exit 1
        fi
        case $OPT in
            INSTALLSTANDALONE)
                Envir
                nimmount
                installaixstandalone
                nimunmount
                ;;
            INSTALLCLUSTERACTIF)
                Envir
                nimmount
                installaixclusteractif
                nimunmount
                ;;
            INSTALLCLUSTERPASSIF)
                Envir
                nimmount
                installaixclusterpassif
                nimunmount
                ;;
            UPDGRADEAGENT)
                nimmount
                upgradeagentaix
                nimunmount
                ;;
            STARTCTMAGTAIX)
                StartctmagtAix
                ;;
            STOPCTMAGTAIX)
                StopctmagtAix
                ;;
            UNINSTALLCTMAIX)
                nimmount
                uninstallCTMAix
                nimunmount
                ;;
            *)
                usage
                ;;
        esac
        ;;


    LINUX)
        echo "OS         : ${OSuname}"
        echo "OS version : ${OSlevel}"
        echo ${OSuname} | grep -i LINUX > /dev/null
        RC=${?}
        if [[ ${RC} != 0 ]] ; then
         echo "################################################"
         echo "ABORTED TOOLS :                                 "
         echo "Selected COMMAND is not for this OS : ${OSuname}"
         echo "################################################"
         exit 1
        fi
        case $OPT in
            INSTALLSTANDALONE)
                Envir
                nimmount
                installlinuxstandalone
                nimunmount
                ;;
            UPDGRADEAGENT)
                nimmount
                upgradeagentlinux
                nimunmount
                ;;
            STARTCTMAGTLINUX)
                StartctmagtLinux
                ;;
            STOPCTMAGTLINUX)
                StopctmagtLinux
                ;;
            UNINSTALLCTMLINUX)
                nimmount
                uninstallCTMLinux
                nimunmount
                ;;
            STARTCTMEM)
                StartctmemLinux
                ;;
            STOPCTMEM)
                StopctmemLinux
                ;;
            STARTCTMSERVER)
                StartctmserverLinux
                ;;
            STOPCTMSERVER)
                StopctmserverLinux
                ;;
            STARTCTMCA)
                StartctmcaLinux
                ;;
            STOPCTMCA)
                StopctmcaLinux
                ;;
            *)
                usage
                ;;
        esac
        ;;


    AUTRE)
        case $OPT in
            MOUNTNIM)
                nimmount
                ;;
            UMOUNTNIM)
                nimunmount
                ;;
            *)
                usage
                ;;
        esac
        ;;


    *)
        usage
        ;;

esac

exit 0