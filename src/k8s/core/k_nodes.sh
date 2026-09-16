#!/usr/bin/env bash

# Shared globals (NAMESPACE, colors, resource names) are defined by
# bin/kubelynx.sh and sibling modules sourced into the same shell.
# shellcheck disable=SC2154,SC2086,SC2155,SC2221,SC2222,SC2317,SC2162,SC2034,SC2031,SC2030,SC2015,SC2207,SC2001,SC2181,SC2140,SC2046
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

# Display node taints
