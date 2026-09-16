#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
# shellcheck disable=SC2034  # Variables used via nameref

# ============================================================================
# Enhanced Menu UI System
# ============================================================================
# Provides: breadcrumbs, contextual descriptions, confirmation prompts,
#           and professional ANSI styling

# ANSI Color Codes
readonly MENU_BLUE='\033[0;34m'
readonly MENU_GREEN='\033[0;32m'
readonly MENU_YELLOW='\033[0;33m'
readonly MENU_RED='\033[0;31m'
readonly MENU_CYAN='\033[0;36m'
readonly MENU_BOLD='\033[1m'
readonly MENU_RESET='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

# Print a separator line
menu::print_separator() {
    echo -e "${MENU_CYAN}────────────────────────────────────────────────${MENU_RESET}"
}

# Print breadcrumb navigation
menu::print_breadcrumb() {
    local breadcrumb="$1"
    if [[ -n "$breadcrumb" ]]; then
        echo -e "${MENU_BLUE}${MENU_BOLD}${breadcrumb}${MENU_RESET}"
        menu::print_separator
    fi
}

# Confirm action (returns 0 if yes, 1 if no)
menu::confirm_action() {
    local message="${1:-Are you sure?}"
    local response
    echo -e "${MENU_YELLOW}${message} (y/N)${MENU_RESET} "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================================
# Main Menu Function
# ============================================================================
# show_menu(title, options_array, descriptions_array, breadcrumb, requires_confirmation_array)
#
# Parameters:
#   $1 - Menu title
#   $2 - Array name containing menu options (without $)
#   $3 - Array name containing descriptions (without $)
#   $4 - Breadcrumb string (e.g., "Main Menu > Kubernetes Core Actions")
#   $5 - Array name containing boolean flags for confirmation (optional, without $)
#
# Returns: Selected option text
menu::show_menu() {
    local title="$1"
    local options_array_name="$2"
    local descriptions_array_name="$3"
    local breadcrumb="$4"
    local confirm_array_name="${5:-}"

    # Create arrays from names
    local -n options="$options_array_name"
    local -n descriptions="$descriptions_array_name"

    # Create a temporary file for preview script
    local preview_script
    preview_script=$(create_temp_file "_menu_preview.sh")

    # Build preview script with case statement. Single quotes are intentional:
    # the generated file must contain literal $1 / $selected.
    # shellcheck disable=SC2016
    {
        echo '#!/usr/bin/env bash'
        echo 'selected="$1"'
        echo 'case "$selected" in'

        # Add case entries for each option
        for i in "${!options[@]}"; do
            local opt="${options[i]}"
            local desc="${descriptions[i]:-No description available}"
            # Escape special characters for case statement
            opt_escaped=$(printf '%s' "$opt" | sed 's/[[\.*^$()+?{|]/\\&/g')
            desc_escaped=$(printf '%s' "$desc" | sed "s/\"/\\\\\"/g")
            echo "    \"$opt_escaped\")"
            echo "        echo -e \"${MENU_CYAN}${MENU_BOLD}Description:${MENU_RESET}\""
            echo "        echo -e \"${MENU_GREEN}$desc_escaped${MENU_RESET}\""
            echo "        ;;"
        done

        echo '    *)'
        echo "        echo -e \"${MENU_YELLOW}No description available${MENU_RESET}\""
        echo '        ;;'
        echo 'esac'
    } >"$preview_script"

    chmod +x "$preview_script"

    # Display breadcrumb
    if [[ -n "$breadcrumb" ]]; then
        clear
        menu::print_breadcrumb "$breadcrumb"
    fi

    # Build fzf command with preview
    local selected
    selected=$(printf '%s\n' "${options[@]}" \
        | fzf \
            --prompt="${MENU_GREEN}${MENU_BOLD}${title} ${MENU_CYAN}>${MENU_RESET} " \
            --border=rounded \
            --height=40% \
            --border-label="${MENU_BLUE}${MENU_BOLD}Kubernetes Doctor${MENU_RESET}" \
            --preview="bash '$preview_script' {}" \
            --preview-window=right:40%:wrap \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:green,border:blue,header:yellow,preview-bg:#000000,preview-fg:#00FF00")

    # Clean up preview script
    rm -f "$preview_script"

    # Check if confirmation is required
    if [[ -n "$selected" && -n "$confirm_array_name" ]]; then
        local -n confirm_flags="$confirm_array_name"
        for i in "${!options[@]}"; do
            if [[ "${options[i]}" == "$selected" ]]; then
                if [[ "${confirm_flags[i]:-false}" == "true" ]]; then
                    if ! menu::confirm_action "Are you sure you want to proceed?"; then
                        echo -e "${MENU_YELLOW}Action cancelled.${MENU_RESET}"
                        echo "" # Return empty to indicate cancellation
                        return 0
                    fi
                fi
                break
            fi
        done
    fi

    # Return selected option (trimmed, or empty if cancelled)
    if [[ -n "$selected" ]]; then
        # Trim leading/trailing whitespace
        selected=$(echo "$selected" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "$selected"
    fi
}

# ============================================================================
# Simplified Menu Function (without preview for compatibility)
# ============================================================================
menu::show_menu_simple() {
    local title="$1"
    local options_array_name="$2"
    local breadcrumb="$3"

    local -n options="$options_array_name"

    # Display breadcrumb
    if [[ -n "$breadcrumb" ]]; then
        clear
        menu::print_breadcrumb "$breadcrumb"
    fi

    # Build fzf command
    local selected
    selected=$(printf '%s\n' "${options[@]}" \
        | fzf \
            --prompt="${MENU_GREEN}${MENU_BOLD}${title} ${MENU_CYAN}>${MENU_RESET} " \
            --border=rounded \
            --height=40% \
            --border-label="${MENU_BLUE}${MENU_BOLD}Kubernetes Doctor${MENU_RESET}" \
            --color="fg:#00FFFF,bg:#000000,hl:#00FF00,fg+:#FFFFFF,bg+:#000000,prompt:green,border:blue,header:yellow")

    echo "$selected"
}

# Responsive layout
