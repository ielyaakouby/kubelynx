#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
display_all_resources_of_namespace() {

    local ns
    ns=$(select_namespace) || return

    printf "+-------------+------------------------------+\n"
    printf "| %-11s | %-28s |\n" "TYPE" "NAME"
    printf "+-------------+------------------------------+\n"

    kubectl -n "$ns" get all --no-headers -o custom-columns='TYPE:.kind,NAME:.metadata.name' 2>/dev/null \
        | awk '
    {
        kind = $1
        name = $2
        if (kind != current_kind) {
            if (NR != 1) {
                printf "+-------------+------------------------------+\n"
            }
            current_kind = kind
            printf "| %-11s | %-28s |\n", kind, name
        } else {
            printf "| %-11s | %-28s |\n", "", name
        }
    }
    END {
        if (NR > 0) {
            printf "+-------------+------------------------------+\n"
        }
    }'
}

new_count_resource_types() {

    echo -e "${CYAN}\nSelect an option:${RESET}\n"
    echo -e "${GREEN}   1) Count resources in a specific namespace${RESET}"
    echo -e "${GREEN}   2) Count resources in all namespaces${RESET}\n"
    read -rp "  Enter your choice (1 or 2): " choice

    local namespace_option
    if [[ "$choice" == "1" ]]; then
        echo
        read -rp "  Enter the namespace (enter to select one) : " NAMESPACE
        if [[ -z $NAMESPACE ]]; then
            NAMESPACE=$(select_namespace) || exit 1
        fi
        namespace_option="--namespace=$NAMESPACE"
        echo -e "${CYAN}\n  Counting Different Resource Types in namespace: ${YELLOW}$NAMESPACE${RESET}\n"
    elif [[ "$choice" == "2" ]]; then
        namespace_option="--all-namespaces"
        echo -e "${CYAN}\n  Counting Different Resource Types in all namespaces:${RESET}\n"
    else
        echo -e "${RED}  Invalid choice. Please enter 1 or 2.${RESET}\n"
        return
    fi

    # Déclaration d'un tableau pour stocker les résultats
    declare -A resource_counts

    # Récupération des comptes pour chaque type de ressource
    resource_counts[DaemonSets]=$(kubectl get daemonsets "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Deployments]=$(kubectl get deployments "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[StatefulSets]=$(kubectl get statefulsets "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Pods]=$(kubectl get pods "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Secrets]=$(kubectl get secrets "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[ConfigMaps]=$(kubectl get configmaps "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Services]=$(kubectl get services "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Ingresses]=$(kubectl get ingresses "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[PersistentVolumeClaims]=$(kubectl get pvc "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[PersistentVolumes]=$(kubectl get pv --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[CronJobs]=$(kubectl get cronjobs "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[Jobs]=$(kubectl get jobs "$namespace_option" --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[CRDs]=$(kubectl get crds --no-headers 2>/dev/null | wc -l || echo 0)
    resource_counts[StorageClasses]=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l || echo 0)
    # networkpolicy
    #

    # Initialisation du total
    total=0

    # Définir un tableau avec l'ordre spécifique des types de ressources
    ordered_resources=("DaemonSets" "Deployments" "StatefulSets" "Pods" "Secrets" "ConfigMaps" "Services"
        "Ingresses" "PersistentVolumeClaims" "PersistentVolumes" "CronJobs" "Jobs" "CRDs" "StorageClasses")

    # Créer un tableau temporaire pour stocker les ressources et leurs comptes
    {
        echo -e "${YELLOW}  Count Resource Type${RESET}\n"
        for resource in "${ordered_resources[@]}"; do
            count=${resource_counts[$resource]}          # Récupérer le compte
            printf "%-30s %d\n" "    $resource" "$count" # Imprimer le type de ressource et son compte
            total=$((total + count))                     # Ajouter au total
        done
        echo -e "${MAGENTA}    --------------------------------${RESET}"

        printf "%-30s %d\n" "    Total" "$total" # Afficher le total des ressources
    }

    echo
}

get_nodes_list_sort_by_age() {
    # kubectl get nodes -owide --sort-by='.metadata.creationTimestamp'
    kubectl get nodes | awk 'NR==1{print;next} 
    {
        age = $4;
        days = 0; hours = 0; minutes = 0;
        
        # Extract days if present
        if (age ~ /[0-9]+d/) {
            split(age, d, "d");
            days = d[1];
            age = d[2];
        }
        
        # Extract hours if present
        if (age ~ /[0-9]+h/) {
            split(age, h, "h");
            hours = h[1];
            age = h[2];
        }
        
        # Extract minutes if present
        if (age ~ /[0-9]+m/) {
            split(age, m, "m");
            minutes = m[1];
        }

        # Calculate total age in minutes
        total_age = days * 1440 + hours * 60 + minutes;
        print $0, total_age;
    }' | sort -k6,6n | awk '{$NF=""; print $0}' | column -t

}
