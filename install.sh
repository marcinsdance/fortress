#!/bin/bash

set -e

readonly REPO_URL="https://github.com/marcinsdance/fortress.git"
INSTALL_BRANCH="master"

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
      -h|--help)
        echo "Usage: $0 [--branch <branch_name>] [--tag <tag_name>]"
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
    msg_warning "Cannot detect OS. /etc/os-release not found. Proceed at your own risk."
    return
  fi

  source /etc/os-release
  case "${ID}" in
    rocky|ubuntu|debian)
      msg_success "Detected supported OS: ${PRETTY_NAME}"
      ;;
    *)
      msg_warning "Detected unsupported OS: ${PRETTY_NAME}."
      read -p "Fortress is tested on Rocky/Ubuntu/Debian. Continue anyway? (y/N) " -n 1 -r
      echo
      if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        msg_error "Installation cancelled by user."
      fi
      ;;
  esac
}

confirm_installation() {
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
  trap 'echo "Cleaning up..."; rm -rf "$tmp_dir"' EXIT

  msg_info "Cloning Fortress repository ('${INSTALL_BRANCH}' branch/tag) into a temporary directory..."
  if ! git clone --depth 1 --branch "$INSTALL_BRANCH" "$REPO_URL" "$tmp_dir"; then
    msg_error "Failed to clone repository. Is '${INSTALL_BRANCH}' a valid branch/tag?"
  fi

  msg_info "Starting the main Fortress installer..."
  if ! (cd "$tmp_dir" && ./bin/fortress install); then
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
  msg_success "Fortress installation process has been successfully initiated."
  msg_info "Follow the prompts from the installer. Generated passwords and details will be shown upon its completion."
}

main "$@"
