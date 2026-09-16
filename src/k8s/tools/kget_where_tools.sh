#!/usr/bin/env bash
# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046

kget_where_usage() {
    echo "kget_where_usage: $0 <pod> where label is/in \"label1,label2,...\""
}

validate_args() {
    echo "@: $*"
    if [[ "$#" -ne 5 ]]; then
        kget_where_usage
        return 1
    fi

    if [[ "$2" != "where" || "$3" != "label" || ! ("$4" == "is" || "$4" == "in") ]]; then
        kget_where_usage
        return 1
    fi
}

extract_labels() {
    local wheree="$1"
    local input_labels="$2"
    if [[ $wheree == "is" ]]; then
        labelss="$input_labels"
    fi
    if [[ $wheree == "in" ]]; then
        labelss=$(echo $input_labels | sed 's/,/|/g' | sed 's/ //g')
    fi
    echo $labelss
}

get_resource_info() {
    local RESOURCE="$1"
    local LABELS="$2"
    local reset="\033[0m" # Reset color
    declare -a colors=(
        "\033[0;31m" "\033[0;32m" "\033[0;33m" "\033[0;34m"
        "\033[0;35m" "\033[0;36m" "\033[0;37m" "\033[1;34m"
        "\033[1;32m" "\033[1;33m" "\033[1;36m" "\033[1;31m"
    )

    echo -e "${reset}NAMESPACE\tPOD\tSTATUS\tREADY\tAGE"
    echo "kubectl get $RESOURCE --all-namespaces --show-labels | grep -iE $labelss 2>/dev/null"
    result="$(kubectl get $RESOURCE --all-namespaces --show-labels | grep -iE "$labelss" 2>/dev/null)"
    echo $result
    #   kubectl get "$RESOURCE" --all-namespaces --show-labels 2>/dev/null | \
    #   grep -iE "$LABEL" | \
    #   awk -v colors="${colors[*]}" -v reset="$reset" '
    #   BEGIN {
    #       split(colors, colorArray, " ");
    #       namespaceColorIndex = 0;
    #   }
    #   {
    #       namespace = $1;  # Assuming namespace is the first column
    #       # Assign color if the namespace is new
    #       if (!(namespace in colorMap)) {
    #           colorMap[namespace] = colorArray[++namespaceColorIndex % length(colorArray)];
    #       }
    #       # Print the line with the assigned color
    #       printf "%s%s\t%s\t%s\t%s\t%s%s\n", colorMap[namespace], $1, $2, $3, $4, $6, reset;
    #
    #   }' | column -t
    #printf "%s%s\t%s\t%s\t%s\t%s\t%s%s\n", colorMap[namespace], $1, $2, $3, $4, $6, $7, reset;
    #done
}

_kget_where_1_completion() {
    local pods
    pods=$(kubectl get pods --no-headers -o custom-columns=":metadata.name") # Fetch pod names

    local commands="where"
    local labels="label"

    local current_word="${COMP_WORDS[COMP_CWORD]}"

    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$pods" -- "$current_word"))
    elif [[ $COMP_CWORD -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$current_word"))
    elif [[ $COMP_CWORD -eq 3 ]]; then
        COMPREPLY=($(compgen -W "$labels" -- "$current_word"))
    elif [[ $COMP_CWORD -eq 4 ]]; then
        COMPREPLY=($(compgen -W "is in" -- "$current_word"))
    elif [[ $COMP_CWORD -eq 5 ]]; then
        COMPREPLY=($(compgen -W "app.kubernetes.io/name=vm,label1=value1" -- "$current_word")) # Example labels
    fi
}

kget_where() {
    validate_args "$@"
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    local RESOURCE="$1"
    local labelss

    if [[ $4 == "is" ]]; then
        labelss="$5"
    fi
    if [[ $4 == "in" ]]; then
        labelss=$(echo $5 | sed 's/,/|/g' | sed 's/ //g')
    fi

    echo "labelss:: $labelss"
    declare -a colors=(
        "\033[0;31m" "\033[0;32m" "\033[0;33m" "\033[0;34m"
        "\033[0;35m" "\033[0;36m" "\033[0;37m" "\033[1;34m"
        "\033[1;32m" "\033[1;33m" "\033[1;36m" "\033[1;31m"
    )

    echo -e "${reset}NAMESPACE\tPOD\tSTATUS\tREADY\tAGE"

    kubectl get $RESOURCE --all-namespaces --show-labels | grep -iE "$labelss" 2>/dev/null
}

complete -F _kget_where_1_completion kget_where
