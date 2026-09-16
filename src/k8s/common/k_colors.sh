#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# colors.sh - ANSI color definitions for reuse
# shellcheck disable=SC2034  # Some variables may be unused in this file but used when sourced

# ─── Basic Colors ─────────────────────────────────────────────────────────
RESET='\033[0m'
NC="$RESET" # No Color alias

BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# ─── Bold (Light) Colors ──────────────────────────────────────────────────
BOLD='\033[1m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
LIGHT_YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_MAGENTA='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
LIGHT_WHITE='\033[1;37m'

# ─── Extended 256-color codes (for terminals that support it) ─────────────
ORANGE='\033[38;5;208m'
COLOR_ORANGE='\033[38;5;214m'
COLOR_LIGHT_RED='\033[38;5;203m'
GRAY='\033[1;30m'

# ─── Aliases (for semantic consistency) ───────────────────────────────────
COLOR_RED="$LIGHT_RED"
COLOR_GREEN="$LIGHT_GREEN"
COLOR_YELLOW="$LIGHT_YELLOW"
COLOR_CYAN="$LIGHT_CYAN"
COLOR_RESET="$RESET"

print_color() {
    local color_name="$1"
    shift
    local message="$*"

    case "$color_name" in
        red) echo -e "${RED}${message}${RESET}" ;;
        green) echo -e "${GREEN}${message}${RESET}" ;;
        yellow) echo -e "${YELLOW}${message}${RESET}" ;;
        blue) echo -e "${BLUE}${message}${RESET}" ;;
        magenta) echo -e "${MAGENTA}${message}${RESET}" ;;
        cyan) echo -e "${CYAN}${message}${RESET}" ;;
        light_red) echo -e "${LIGHT_RED}${message}${RESET}" ;;
        light_green) echo -e "${LIGHT_GREEN}${message}${RESET}" ;;
        light_yellow) echo -e "${LIGHT_YELLOW}${message}${RESET}" ;;
        light_blue) echo -e "${LIGHT_BLUE}${message}${RESET}" ;;
        light_magenta) echo -e "${LIGHT_MAGENTA}${message}${RESET}" ;;
        light_cyan) echo -e "${LIGHT_CYAN}${message}${RESET}" ;;
        orange) echo -e "${ORANGE}${message}${RESET}" ;;
        gray) echo -e "${GRAY}${message}${RESET}" ;;
        bold) echo -e "${BOLD}${message}${RESET}" ;;
        *) echo -e "$message" ;;
    esac
}

#print_color green "✔ Opération réussie"
#print_color red "❌ Une erreur est survenue"
#print_color light_yellow "⚠ Attention : seuil dépassé"
#print_color gray "Information de debug"

# Couleurs standard
CLR_RESET="\e[0m"
CLR_BOLD="\e[1m"

# Couleurs sémantiques
CLR_INFO="\e[36m"    # Cyan
CLR_WARN="\e[33m"    # Jaune
CLR_SUCCESS="\e[32m" # Vert
CLR_ERROR="\e[31m"   # Rouge
CLR_CONTEXT="\e[34m" # Bleu

# Icônes personnalisables
ICON_INFO="[i]"
ICON_ARROW="[→]"
ICON_CHECK="[✓]"
ICON_FAIL="[x]"
ICON_NEW="[✔]"

# Extended 256-color support
