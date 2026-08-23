#!/bin/bash

OUTBOUND_FILE="/opt/menu-singbox-vvc/data/outbound.json"

mkdir -p "$(dirname "$OUTBOUND_FILE")"
[ ! -f "$OUTBOUND_FILE" ] && echo "[]" > "$OUTBOUND_FILE"

# Menu quản lý Outbound & Relay
render_outbound_menu() {
    while true; do
        clear
        echo "================================================================"
        echo "||                  QUẢN LÝ OUTBOUND & RELAY                  ||"
        echo "================================================================"
        list_outbounds_table
        echo "================================================================"
        echo " 1. Thêm Outbound Thủ Công"
        echo " 2. Thêm Outbound từ Link Chia Sẻ (Share Link)"
        echo " 3. Sửa Outbound"
        echo " 4. Xóa Outbound"
        echo " 0. Quay lại Menu Chính"
        echo "================================================================"
        read -p " Vui lòng chọn một chức năng [0-4]: " choice

        case "$choice" in
            1)
                add_outbound_manual
                ;;
            2)
                add_outbound_from_link
                ;;
            3)
                edit_outbound
                ;;
            4)
                delete_outbound
                ;;
            0)
                break
                ;;
            *)
                echo -e "\033[31m[LỖI] Lựa chọn không hợp lệ, vui lòng chọn từ 0 đến 4.\033[0m"
                sleep 1
                ;;
        esac
    done
}

# Hiển thị bảng danh sách outbound
list_outbounds_table() {
    echo " Danh sách Outbound hiện tại:"
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo " (Chưa có outbound nào được cấu hình)"
        return
    fi
    
    echo "----------------------------------------------------------------"
    printf "%-4s | %-20s | %-12s | %-20s\n" "STT" "Tag" "Loại (Type)" "Địa chỉ:Cổng"
    echo "----------------------------------------------------------------"
    
    local count
    count=$(jq length "$OUTBOUND_FILE")
    for ((i=0; i<count; i++)); do
        local tag type server port
        tag=$(jq -r --argjson idx "$i" '.[$idx].tag // "N/A"' "$OUTBOUND_FILE")
        type=$(jq -r --argjson idx "$i" '.[$idx].type // "N/A"' "$OUTBOUND_FILE")
        server=$(jq -r --argjson idx "$i" '.[$idx].server // "N/A"' "$OUTBOUND_FILE")
        port=$(jq -r --argjson idx "$i" '.[$idx].server_port // .[$idx].port // "N/A"' "$OUTBOUND_FILE")
        printf "%-4d | %-20s | %-12s | %-20s\n" "$((i+1))" "$tag" "$type" "$server:$port"
    done
    echo "----------------------------------------------------------------"
}

# Thêm outbound thủ công
add_outbound_manual() {
    echo "--------------------------------------------------"
    echo " THÊM OUTBOUND THỦ CÔNG"
    echo "--------------------------------------------------"
    
    read -p "Nhập Tag (Tên định danh duy nhất): " tag
    if [ -z "$tag" ]; then
        echo -e "\033[31m[LỖI] Tag không được để trống!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local exists
    exists=$(jq --arg t "$tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "\033[31m[LỖI] Tag '$tag' đã tồn tại! Vui lòng chọn tên khác.\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Loại Outbound (vd: vless, vmess, trojan, hysteria2, tuic, socks, shadowsocks): " type
    if [ -z "$type" ]; then
        echo -e "\033[31m[LỖI] Loại outbound không được để trống!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Địa chỉ Server: " server
    if [ -z "$server" ]; then
        echo -e "\033[31m[LỖI] Địa chỉ Server không được để trống!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Cổng (Port): " port
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "\033[31m[LỖI] Cổng (Port) phải là một số nguyên hợp lệ!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    # Lưu theo đúng chuẩn sing-box (server_port)
    jq --arg t "$tag" --arg tp "$type" --arg s "$server" --argjson p "$port" \
       '. += [{"type": $tp, "tag": $t, "server": $s, "server_port": $p}]' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"

    echo -e "\033[32m[THÀNH CÔNG] Đã thêm outbound '$tag' thành công!\033[0m"
    
    # Gọi hàm build cấu hình hệ thống
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi
    
    read -p "Nhấn Enter để tiếp tục..."
}

# Thêm outbound từ link chia sẻ
add_outbound_from_link() {
    echo "--------------------------------------------------"
    echo " THÊM OUTBOUND TỪ LINK CHIA SẺ"
    echo "--------------------------------------------------"
    read -p "Dán link chia sẻ (vless://, vmess://, trojan://, hy2://, tuic://, socks://, ss://...): " link
    if [ -z "$link" ]; then
        echo -e "\033[31m[LỖI] Link không được để trống!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local proto="${link%%://*}"
    local remainder="${link#*://}"
    local tag=""

    if [[ "$remainder" == *#* ]]; then
        tag="${remainder#*#}"
        tag=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$tag'))" 2>/dev/null || echo "$tag")
        remainder="${remainder%%#*}"
    else
        tag="node_$(date +%s)"
    fi

    local exists
    exists=$(jq --arg t "$tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
    if [ "$exists" -gt 0 ]; then
        tag="${tag}_$(date +%s)"
    fi

    local server=""
    local port=""
    local type="$proto"

    case "$proto" in
        hy2|hysteria2) type="hysteria2" ;;
        socks5|socks) type="socks" ;;
        ss|shadowsocks) type="shadowsocks" ;;
        vless) type="vless" ;;
        vmess) type="vmess" ;;
        trojan) type="trojan" ;;
        tuic) type="tuic" ;;
        *) type="$proto" ;;
    esac

    local authority="${remainder%%\?*}"
    if [[ "$authority" == *@* ]]; then
        authority="${authority#*@}"
    fi

    if [[ "$authority" == \[*\]* ]]; then
        server="${authority%%\]*}]"
        port="${authority##*\]:}"
    else
        server="${authority%%:*}"
        port="${authority##*:}"
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        port="443"
    fi

    if [ -z "$server" ]; then
        echo -e "\033[31m[LỖI] Không thể phân tích được địa chỉ Server từ link này.\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --arg t "$tag" --arg tp "$type" --arg s "$server" --argjson p "$port" --arg l "$link" \
       '. += [{"type": $tp, "tag": $t, "server": $s, "server_port": $p, "raw_link": $l}]' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"

    echo -e "\033[32m[THÀNH CÔNG] Đã thêm outbound '$tag' (Loại: $type, Server: $server:$port) thành công!\033[0m"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi
    
    read -p "Nhấn Enter để tiếp tục..."
}

# Sửa outbound hiện có
edit_outbound() {
    echo "--------------------------------------------------"
    echo " SỬA OUTBOUND"
    echo "--------------------------------------------------"
    
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "\033[33m[CẢNH BÁO] Không có outbound nào trong hệ thống để sửa.\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_outbounds_table
    read -p "Nhập số thứ tự (STT) của outbound cần sửa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "\033[31m[LỖI] STT phải là một số nguyên hợp lệ!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$OUTBOUND_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "\033[31m[LỖI] Số thứ tự ($index_input) vượt quá giới hạn danh sách!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local old_tag old_type old_server old_port
    old_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$OUTBOUND_FILE")
    old_type=$(jq -r --argjson i "$idx" '.[$i].type' "$OUTBOUND_FILE")
    old_server=$(jq -r --argjson i "$idx" '.[$i].server // ""' "$OUTBOUND_FILE")
    old_port=$(jq -r --argjson i "$idx" '.[$i].server_port // .[$i].port // 0' "$OUTBOUND_FILE")

    echo "Đang sửa Outbound: $old_tag"
    read -p "Nhập Tag mới [Mặc định: $old_tag]: " new_tag
    new_tag="${new_tag:-$old_tag}"

    if [ "$new_tag" != "$old_tag" ]; then
        local exists
        exists=$(jq --arg t "$new_tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
        if [ "$exists" -gt 0 ]; then
            echo -e "\033[31m[LỖI] Tag '$new_tag' đã bị trùng với outbound khác!\033[0m"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    read -p "Nhập Loại mới [Mặc định: $old_type]: " new_type
    new_type="${new_type:-$old_type}"

    read -p "Nhập Server mới [Mặc định: $old_server]: " new_server
    new_server="${new_server:-$old_server}"

    read -p "Nhập Cổng mới [Mặc định: $old_port]: " new_port
    new_port="${new_port:-$old_port}"

    if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        echo -e "\033[31m[LỖI] Cổng (Port) phải là một số nguyên hợp lệ!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --argjson i "$idx" --arg t "$new_tag" --arg tp "$new_type" --arg s "$new_server" --argjson p "$new_port" \
       '.[$i] = {"type": $tp, "tag": $t, "server": $s, "server_port": $p}' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"

    echo -e "\033[32m[THÀNH CÔNG] Đã cập nhật outbound thành công!\033[0m"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Xóa outbound
delete_outbound() {
    echo "--------------------------------------------------"
    echo " XÓA OUTBOUND"
    echo "--------------------------------------------------"
    
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "\033[33m[CẢNH BÁO] Không có outbound nào để xóa.\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_outbounds_table
    read -p "Nhập số thứ tự (STT) của outbound cần xóa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "\033[31m[LỖI] STT phải là một số nguyên hợp lệ!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$OUTBOUND_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "\033[31m[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!\033[0m"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local target_tag
    target_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$OUTBOUND_FILE")

    read -p "Bạn có chắc chắn muốn xóa outbound '$target_tag' không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        jq --argjson i "$idx" 'del(.[$i])' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"
        echo -e "\033[32m[THÀNH CÔNG] Đã xóa outbound '$target_tag' khỏi hệ thống!\033[0m"
        
        if declare -f build_and_apply_config > /dev/null; then
            build_and_apply_config
        fi
    else
        echo "Đã hủy thao tác xóa."
    fi

    read -p "Nhấn Enter để tiếp tục..."
}