#!/bin/bash
#
# Fortress: Professional, Non-Interactive 'One-Liner' Installer
#
# Version: 4.0.1
# Features:
# - Non-interactive mode (-y, --yes) for automation (e.g., Ansible)
# - Root privilege verification
# - Dependency checks (git, docker)
# - OS compatibility check
# - Argument parsing (--branch, --tag, --admin-email, --fortress-domain, --debug)
# - Colored log output
# - Reliable temporary file cleanup
#
set -e

# --- Configuration ---
readonly REPO_URL="https://github.com/marcinsdance/fortress.git"
INSTALL_BRANCH="main"
NON_INTERACTIVE=false
DEBUG_MODE=false

ADMIN_EMAIL_CLI=""
FORTRESS_DOMAIN_CLI=""

# --- Colors and Logging Functions ---
setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]]; then
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_CYAN='\033[0;36m'
  else
    COLOR_RESET=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
  fi
}

msg() {
  echo -e "${2}${1}${COLOR_RESET}"
}

msg_info() { msg "INFO: $1" "${COLOR_CYAN}"; }
msg_success() { msg "SUCCESS: $1" "${COLOR_GREEN}"; }
msg_warning() { msg "WARN: $1" "${COLOR_YELLOW}"; }
msg_error() { msg "ERROR: $1" "${COLOR_RED}"; exit 1; }

# --- Script Logic ---
print_header() {
  cat << "EOF"
    ___              _
   / __\___  _ __ __| |_ __ ___  ___ ___
  / _\/ _ \| '__/ _` | '__/ _ \/ __/ __|
 / / | (_) | | | (_| | | |  __/\__ \__ \
 \/   \___/|_|  \__,_|_|  \___||___/___/

EOF
  msg "Single VPS Production Deployment Tool Installer" "${COLOR_CYAN}"
  echo ""
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch|--tag)
        INSTALL_BRANCH="$2"
        shift 2
        ;;
      -y|--yes)
        NON_INTERACTIVE=true
        shift 1
        ;;
      --admin-email)
        ADMIN_EMAIL_CLI="$2"
        shift 2
        ;;
      --fortress-domain)
        FORTRESS_DOMAIN_CLI="$2"
        shift 2
        ;;
      --debug)
        DEBUG_MODE=true
        shift 1
        ;;
      -h|--help)
        echo "Usage: $0 [--branch <name>] [--tag <name>] [-y|--yes] [--admin-email <email>] [--fortress-domain <domain>] [--debug]"
        echo ""
        echo "Options:"
        echo "  --branch <name>     Install from a specific branch."
        echo "  --tag <name>        Install a specific tag."
        echo "  -y, --yes           Bypass confirmation prompts for non-interactive/automated installation."
        echo "  --admin-email <email> Email for Let's Encrypt (required for non-interactive install)." # Zaktualizowany opis
        echo "  --fortress-domain <domain> Primary domain for Fortress services (required for non-interactive install)." # Zaktualizowany opis
        echo "  --debug             Enable debug mode (set -x) for the main Fortress installer."
        exit 0
        ;;
      *)
        msg_error "Unknown argument: $1"
        ;;
    esac
  done

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    if [[ -z "${ADMIN_EMAIL_CLI}" ]]; then
      msg_error "In non-interactive mode (--yes), --admin-email is required."
    fi
    if [[ -z "${FORTRESS_DOMAIN_CLI}" ]]; then
      msg_error "In non-interactive mode (--yes), --fortress-domain is required."
    fi
  fi
}

check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    msg_error "This script must be run as root. Please use 'sudo'."
  fi
}

check_dependencies() {
  msg_info "Checking for required dependencies..."
  local missing_deps=()
  for dep in git docker; do
    if ! command -v "$dep" &>/dev/null; then
      missing_deps+=("$dep")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    msg_error "Missing dependencies: ${missing_deps[*]}. Please install them and try again."
  fi
  msg_success "All dependencies are satisfied."
}

check_os() {
  msg_info "Checking OS compatibility..."
  if [[ ! -f /etc/os-release ]]; then
    msg_warning "Cannot detect OS: /etc/os-release not found."
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        msg_error "Aborting in non-interactive mode."
    fi
    read -p "Proceed at your own risk? (y/N) " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        msg_error "Installation cancelled by user."
    fi
    return
  fi

  source /etc/os-release
  case "${ID}" in
    rocky)
      msg_success "Detected supported OS: ${PRETTY_NAME}"
      ;;
    *)
      local warning_msg="Detected OS '${PRETTY_NAME}'. Fortress is officially tested on Rocky Linux 9."
      if [[ "$NON_INTERACTIVE" == "true" ]]; then
        msg_error "${warning_msg} Aborting in non-interactive mode."
      fi
      msg_warning "${warning_msg}"
      read -p "Proceed with the installation at your own risk? (y/N) " -n 1 -r
      echo
      if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        msg_error "Installation cancelled by user."
      fi
      ;;
  esac
}

confirm_installation() {
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    msg_info "Non-interactive mode enabled. Bypassing confirmation."
    return
  fi

  echo ""
  msg_info "The script is ready to install Fortress from branch/tag: '${INSTALL_BRANCH}'"
  read -p "Do you want to proceed with the installation? (Y/n) " -r
  if [[ ! "$REPLY" =~ ^([Yy][Ee][Ss]|[Yy]|)$ ]]; then
      msg_error "Installation cancelled by user."
  fi
}

clone_and_install() {
  local tmp_dir
  tmp_dir=$(mktemp -d -t fortress-install-XXXXXX)
  trap 'echo "Cleaning up temporary files..."; rm -rf "$tmp_dir"' EXIT

  msg_info "Cloning Fortress repository ('${INSTALL_BRANCH}' branch/tag) into a temporary directory..."
  if ! git clone --depth 1 --branch "$INSTALL_BRANCH" "$REPO_URL" "$tmp_dir"; then
    msg_error "Failed to clone repository. Is '${INSTALL_BRANCH}' a valid branch/tag?"
  fi

  msg_info "Starting the main Fortress installer..."

  local fortress_install_env=""
  if [[ -n "${ADMIN_EMAIL_CLI}" ]]; then
    fortress_install_env+="ADMIN_EMAIL='${ADMIN_EMAIL_CLI}' "
  fi
  if [[ -n "${FORTRESS_DOMAIN_CLI}" ]]; then
    fortress_install_env+="FORTRESS_DOMAIN='${FORTRESS_DOMAIN_CLI}' "
  fi

  local fortress_install_debug_option=""
  if [[ "$DEBUG_MODE" == "true" ]]; then
    fortress_install_debug_option="--debug"
  fi

  if ! (cd "$tmp_dir" && env $fortress_install_env ./bin/fortress install $fortress_install_debug_option); then
    msg_error "The main Fortress installer failed. Please check the logs above for details."
  fi
}

main() {
  setup_colors
  parse_args "$@"
  print_header
  check_root
  check_dependencies
  check_os
  confirm_installation
  clone_and_install

  msg_info "Installing 'fortress' command to /usr/local/bin/fortress..."
    if [[ -f "/opt/fortress/bin/fortress" ]]; then
      sudo ln -sf "/opt/fortress/bin/fortress" "/usr/local/bin/fortress"
      sudo chmod +x "/opt/fortress/bin/fortress"
      msg_success "'fortress' command is now globally available."
    else
      msg_error "Failed to create symlink: /opt/fortress/bin/fortress not found. Manual intervention required."
    fi

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        msg_success "Fortress installation process has been successfully initiated and completed in non-interactive mode."
        msg_info "Generated passwords and details are available in /opt/fortress/config/fortress.env"
    else
        msg_success "Fortress installation process has been successfully initiated."
        msg_info "Generated passwords and details will be shown upon its completion."
    fi
}

main "$@"
