#!/bin/bash

# =======================================================================================
# Script de Inventarios xcp-ng
# Desarrollado por: Cristian Omar Jiménez Sánchez
# Github: crisomarjs
#
# Ejecución: bash inevntarios_xcp.sh
#
# Este script extare el inventario de maquinas virtuales, incluyendo
# hotsname, host server, cpu, ram asignada, SO, cantdad de discos y tamaño, mac, ip
# =======================================================================================

# Validar entorno
if ! command -v xe &>/dev/null; then
    echo "ERROR: comando 'xe' no encontrado." >&2
    exit 1
fi

hypervisor_name=$(hostname)
pool_name=$(xe pool-list params=name-label --minimal)
current_date=$(date +"%Y-%m-%d")
output_file="inventario_${hypervisor_name}_${pool_name}_${current_date}.csv"

convert_iso8601_to_date() {
    local iso_date="$1"
    if [[ "$iso_date" =~ ^[0-9]{8}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        local cleaned
        cleaned=$(echo "$iso_date" | sed -e 's/T/ /' -e 's/Z//')
        echo "$cleaned" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2}) /\1-\2-\3 /'
    else
        echo "N/A"
    fi
}

vm_list=$(xe vm-list is-control-domain=false --minimal)
IFS=',' read -ra vm_array <<< "$vm_list"
total=${#vm_array[@]}
count=0
max_disks=0

# Arrays para guardar todos los datos en memoria
declare -a ALL_VM_NAMES
declare -a ALL_POWER_STATES
declare -a ALL_HOST_NAMES
declare -a ALL_CPU_COUNTS
declare -a ALL_MEMORY_MBS
declare -a ALL_DISK_COUNTS
declare -a ALL_DISK_DATA
declare -a ALL_OS_TYPES
declare -a ALL_UPTIMES
declare -a ALL_MACS
declare -a ALL_IPS

echo "==> Recopilando datos de $total VMs..." >&2

for vm_uuid in "${vm_array[@]}"; do
    vm_uuid=$(echo "$vm_uuid" | xargs)
    [ -z "$vm_uuid" ] && continue

    count=$((count + 1))
    vm_name=$(xe vm-param-get uuid=$vm_uuid param-name=name-label | sed 's/"/""/g')
    echo "  [$count/$total] $vm_name" >&2

    vm_power_state=$(xe vm-param-get uuid=$vm_uuid param-name=power-state)

    host_uuid=$(xe vm-param-get uuid=$vm_uuid param-name=resident-on)
    if [ -n "$host_uuid" ] && [[ "$host_uuid" != "<not"* ]]; then
        host_name=$(xe host-param-get uuid=$host_uuid param-name=name-label)
    else
        host_name="N/A"
    fi

    vm_cpu_count=$(xe vm-param-get uuid=$vm_uuid param-name=VCPUs-max)
    vm_memory_bytes=$(xe vm-param-get uuid=$vm_uuid param-name=memory-static-max)
    vm_memory_mb=$(($vm_memory_bytes / 1024 / 1024))

    # ── Discos ──────────────────────────────────────────────
    vbd_list=$(xe vbd-list vm-uuid=$vm_uuid type=Disk --minimal)
    disk_data=""
    number_of_disks=0

    if [ -n "$vbd_list" ]; then
        IFS=',' read -ra vbd_array <<< "$vbd_list"
        number_of_disks=${#vbd_array[@]}
        for i in "${!vbd_array[@]}"; do
            vbd_uuid=$(echo "${vbd_array[$i]}" | xargs)
            vdi_uuid=$(xe vbd-param-get uuid=$vbd_uuid param-name=vdi-uuid)
            disk_size_bytes=$(xe vdi-param-get uuid=$vdi_uuid param-name=virtual-size)
            disk_gb=$(($disk_size_bytes / 1024 / 1024 / 1024))
            if [ -z "$disk_data" ]; then
                disk_data="$disk_gb"
            else
                disk_data="$disk_data|$disk_gb"
            fi
        done
        # Actualizar el máximo de discos global
        [ "$number_of_disks" -gt "$max_disks" ] && max_disks=$number_of_disks
    fi

    # ── OS ──────────────────────────────────────────────────
    os_type=$(xe vm-param-get uuid=$vm_uuid param-name=os-version 2>/dev/null \
        | grep -oP 'name:\s*\K[^;]+' | xargs)
    [ -z "$os_type" ] && os_type="N/A"

    # ── Uptime ──────────────────────────────────────────────
    if [ "$vm_power_state" == "running" ]; then
        start_timestamp=$(xe vm-param-get uuid=$vm_uuid param-name=start-time 2>/dev/null)
        start_date=$(convert_iso8601_to_date "$start_timestamp")
        if [ "$start_date" != "N/A" ]; then
            start_unix=$(date --date="$start_date" +%s)
            uptime_secs=$(($(date +%s) - start_unix))
            uptime_days=$((uptime_secs / 86400))
            uptime_hours=$(( (uptime_secs % 86400) / 3600 ))
            uptime_minutes=$(( (uptime_secs % 3600) / 60 ))
            uptime="${uptime_days}d ${uptime_hours}h ${uptime_minutes}m"
        else
            uptime="N/A"
        fi
    else
        uptime="N/A"
    fi

    # ── Red: MACs e IPs ─────────────────────────────────────
    vifs=$(xe vif-list vm-uuid=$vm_uuid --minimal)
    networks_info=$(xe vm-param-get uuid=$vm_uuid param-name=networks 2>/dev/null)
    mac_addresses=""
    ip_addresses=""

    IFS=',' read -ra vif_array <<< "$vifs"
    for vif_uuid in "${vif_array[@]}"; do
        vif_uuid=$(echo "$vif_uuid" | xargs)
        [ -z "$vif_uuid" ] && continue
        mac_address=$(xe vif-param-get uuid=$vif_uuid param-name=MAC)
        vif_device=$(xe vif-param-get uuid=$vif_uuid param-name=device)
        ip_address=$(echo "$networks_info" \
            | grep -oP "${vif_device}/ip:\s*\K[0-9.]+" | head -1)
        [ -z "$ip_address" ] && ip_address="N/A"
        mac_addresses+="$mac_address; "
        ip_addresses+="$ip_address; "
    done

    [ ${#mac_addresses} -gt 2 ] && mac_addresses=${mac_addresses::-2}
    [ ${#ip_addresses} -gt 2 ]  && ip_addresses=${ip_addresses::-2}

    # ── Guardar en arrays ────────────────────────────────────
    idx=$((count - 1))
    ALL_VM_NAMES[$idx]="$vm_name"
    ALL_POWER_STATES[$idx]="$vm_power_state"
    ALL_HOST_NAMES[$idx]="$host_name"
    ALL_CPU_COUNTS[$idx]="$vm_cpu_count"
    ALL_MEMORY_MBS[$idx]="$vm_memory_mb"
    ALL_DISK_COUNTS[$idx]="$number_of_disks"
    ALL_DISK_DATA[$idx]="$disk_data"
    ALL_OS_TYPES[$idx]="$os_type"
    ALL_UPTIMES[$idx]="$uptime"
    ALL_MACS[$idx]="$mac_addresses"
    ALL_IPS[$idx]="$ip_addresses"
done

# ── Construir header dinámico ────────────────────────────────
echo "==> Máximo de discos detectado: $max_disks. Generando CSV..." >&2

header="VM Name,VM Power State,Host Server,CPU Count,Memory (MB)"
for ((d=1; d<=max_disks; d++)); do
    header+=",Disk $d (GB)"
done
header+=",Number of Disks,OS Type,Uptime,MAC Addresses,IP Addresses"
echo "$header" > "$output_file"

# ── Escribir filas ───────────────────────────────────────────
total_written=$((count))
for ((idx=0; idx<total_written; idx++)); do
    row="\"${ALL_VM_NAMES[$idx]}\",\"${ALL_POWER_STATES[$idx]}\",\"${ALL_HOST_NAMES[$idx]}\",\"${ALL_CPU_COUNTS[$idx]}\",\"${ALL_MEMORY_MBS[$idx]}\""

    # Expandir discos con | como separador, rellenando con N/A hasta max_disks
    IFS='|' read -ra disks <<< "${ALL_DISK_DATA[$idx]}"
    for ((d=0; d<max_disks; d++)); do
        if [ -n "${disks[$d]}" ]; then
            row+=",\"${disks[$d]}\""
        else
            row+=",\"N/A\""
        fi
    done

    row+=",\"${ALL_DISK_COUNTS[$idx]}\",\"${ALL_OS_TYPES[$idx]}\",\"${ALL_UPTIMES[$idx]}\",\"${ALL_MACS[$idx]}\",\"${ALL_IPS[$idx]}\""
    echo "$row" >> "$output_file"
done

echo "Inventario generado: $output_file"