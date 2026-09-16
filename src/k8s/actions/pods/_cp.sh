#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
ok_kubectl_cp_pod() {
    ensure_pod_and_namespace || return 1

    echo -e "\n🔄 Copy direction:"
    echo -e "  1) \e[34mpod ➜ local\e[0m"
    echo -e "  2) \e[34mlocal ➜ pod\e[0m"
    read -r -p "  ↪ Choose (1 or 2): " direction

    case "$direction" in
        1)
            echo -e "\n📂 Path in pod to copy from:"
            read -r -p "  ↪ " pod_path

            echo -e "\n📂 Local destination path (type 'here' for current dir):"
            read -r -p "  ↪ " local_path
            [[ -z "$local_path" || "$local_path" == "here" ]] && local_path="$(pwd)"

            src="$POD_NAME:$pod_path"
            dest="$local_path"
            msg="🌟 Copied pod ➜ local\n📂 $pod_path → 📥 $local_path"
            ;;
        2)
            echo -e "\n📂 Local path to copy to the pod:"
            read -r -p "  ↪ " local_path

            echo -e "\n📂 Target path in the pod:"
            read -r -p "  ↪ " pod_path

            src="$local_path"
            dest="$POD_NAME:$pod_path"
            msg="🌟 Copied local ➜ pod\n📂 $local_path → 📤 $pod_path"
            ;;
        *)
            display_message red "❌ Invalid choice: select 1 or 2"
            return 1
            ;;
    esac

    echo -e "\n📦 Copying..."
    echo "kubectl cp -n \"$NAMESPACE\" \"$src\" \"$dest\""
    if kubectl cp -n "$NAMESPACE" "$src" "$dest" 2>/dev/null; then
        display_message green "$msg"
    else
        display_message red "🚨 Copy failed. Please verify paths and try again."
    fi
}
