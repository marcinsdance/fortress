#!/usr/bin/env bash
# ~/fortress-source/utils/core.sh

# Colors (example)
COLOR_RESET='\033[0m'; COLOR_GREEN='\033[0;32m'; COLOR_YELLOW='\033[0;33m'; COLOR_RED='\033[0;31m'; COLOR_CYAN='\033[0;36m'

function info() { echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} $1"; }
function warning() { echo -e "${COLOR_YELLOW}WARN:${COLOR_RESET} $1"; }
function error() { >&2 echo -e "${COLOR_RED}ERROR:${COLOR_RESET} $1"; } # Used by trap and can be called directly
function fatal() { error "$1"; exit 1; }

# Add any other globally used utility functions here

function info() {
    echo -e "${COLOR_GREEN}INFO:${COLOR_RESET} $1"
}

function warning() {
    echo -e "${COLOR_YELLOW}WARN:${COLOR_RESET} $1"
}

function error() {
    # This function can be called by scripts or by the trap
    >&2 echo -e "${COLOR_RED}ERROR:${COLOR_RESET} $1"
}

function fatal() {
    error "$1"
    exit 1
}

function success() { # <--- ADD THIS FUNCTION
    echo -e "${COLOR_GREEN}SUCCESS:${COLOR_RESET} $1"
}

