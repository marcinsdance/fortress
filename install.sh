#!/bin/bash
#
# Fortress: Professional, Non-Interactive 'One-Liner' Installer
#
# Version: 4.0
# Features:
# - Non-interactive mode (-y, --yes) for automation (e.g., Ansible)
# - Root privilege verification
# - Dependency checks (git, docker)
# - OS compatibility check
# - Argument parsing (--branch, --tag)
# - Colored log output
# - Reliable temporary file cleanup
#
set -e

# --- Configuration ---
readonly REPO_URL="https://github.com/marcinsdance/fortress.git"
INSTALL_BRANCH="main"
NON_INTERACTIVE=false

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
      -h|--help)
        echo "Usage: $0 [--branch <name>] [--tag <name>] [-y|--yes]"
        echo ""
        echo "Options:"
        echo "  --branch <name>  Install from a specific branch."
        echo "  --tag <name>     Install a specific tag."
        echo "  -y, --yes        Bypass confirmation prompts for non-interactive/automated installation."
        exit 0
        ;;
      *)
        msg_error "Unknown argument: $1"
        ;;
    esac
  done
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
  if ! (cd "$tmp_dir" && ./bin/fortress install); then
    msg_error "The main Fortress installer failed. Please check the logs above for details."
  fi
}

# --- Main execution function ---
main() {
  setup_colors
  parse_args "$@"
  print_header
  check_root
  check_dependencies
  check_os
  confirm_installation
  clone_and_install
  msg_success "Fortress installation process has been successfully initiated."
  msg_info "Follow the prompts from the installer. Generated passwords and details will be shown upon its completion."
}

# Run the script, passing all arguments to main
main "$@"
