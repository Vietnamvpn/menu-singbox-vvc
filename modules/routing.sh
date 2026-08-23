#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
fi

ROUTING_FILE="${INSTALL_DIR}/data/routing.json"
NODES_FILE="${INSTALL_DIR}/data/nodes.json"
OUTBOUND_FILE="${INSTALL_DIR}/data/outbound.json"

mkdir -p "$(dirname "$ROUTING_FILE")"
[ ! -f "$ROUTING_FILE" ] && echo "[]" > "$ROUTING_FILE"

# Menu quản lý Định tuyến (Routing)
render_routing_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${BLUE}||${NC}                  ${YELLOW}QUẢN LÝ ĐỊNH TUYẾN (ROUTING)              ${BLUE}||${NC}"
        echo -e "${BLUE}================================================================${NC}"
        list_routing_table
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Quy tắc Định tuyến"
        echo -e " ${GREEN}2.${NC} Sửa Quy tắc Định tuyến"
        echo -e " ${GREEN}3.${NC} Xóa Quy tắc Định tuyến"
        echo -e " ${RED}0.${NC} Quay lại Menu Chính"
        echo -e "${BLUE}================================================================${NC}"
        read -p " Vui lòng chọn một chức năng [0-3]: " choice

        case "$choice" in
            1)
                add_routing_rule
                ;;
            2)
                edit_routing_rule
                ;;
            3)
                delete_routing_rule
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}[LỖI] Lựa chọn không hợp lệ, vui lòng chọn từ 0 đến 3.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Hiển thị bảng danh sách quy tắc định tuyến
list_routing_table() {
    echo -e " ${CYAN}Danh sách Quy tắc Định tuyến hiện tại:${NC}"
    if [ ! -s "$ROUTING_FILE" ] || [ "$(jq length "$ROUTING_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e " ${YELLOW}(Chưa có quy tắc định tuyến nào được cấu hình)${NC}"
        return
    fi
    
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    printf "${CYAN}%-4s${NC} | ${GREEN}%-25s${NC} | ${BLUE}%-25s${NC}\n" "STT" "Inbound Tag" "Outbound Tag"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    
    local count
    count=$(jq length "$ROUTING_FILE")
    for ((i=0; i<count; i++)); do
        local inbound outbound
        inbound=$(jq -r --argjson idx "$i" '.[$idx].inbound | join(", ")' "$ROUTING_FILE")
        outbound=$(jq -r --argjson idx "$i" '.[$idx].outbound // "N/A"' "$ROUTING_FILE")
        printf "%-4d | %-25s | %-25s\n" "$((i+1))" "$inbound" "$outbound"
    done
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
}

# Thêm quy tắc định tuyến mới
add_routing_rule() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} THÊM QUY TẮC ĐỊNH TUYẾN${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$NODES_FILE" ] || [ "$(jq length "$NODES_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${RED}[LỖI] Chưa có Inbound Node nào được tạo. Vui lòng tạo Inbound trước!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${RED}[LỖI] Chưa có Outbound nào được thêm. Vui lòng thêm Outbound trước!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    echo -e "${CYAN}Danh sách Inbound Nodes có sẵn:${NC}"
    jq -r '.[] | "- " + .tag' "$NODES_FILE"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Nhập Tag của Inbound cần chuyển tiếp: " in_tag

    if [ -z "$in_tag" ]; then
        echo -e "${RED}[LỖI] Inbound tag không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local node_exists
    node_exists=$(jq --arg t "$in_tag" '[.[] | select(.tag == $t)] | length' "$NODES_FILE")
    if [ "$node_exists" -eq 0 ]; then
        echo -e "${RED}[LỖI] Không tìm thấy Inbound với tag '$in_tag'!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    echo -e "${CYAN}Danh sách Outbounds có sẵn:${NC}"
    jq -r '.[] | "- " + .tag' "$OUTBOUND_FILE"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Nhập Tag của Outbound đích: " out_tag

    if [ -z "$out_tag" ]; then
        echo -e "${RED}[LỖI] Outbound tag không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local outbound_exists
    outbound_exists=$(jq --arg t "$out_tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
    if [ "$outbound_exists" -eq 0 ]; then
        echo -e "${RED}[LỖI] Không tìm thấy Outbound với tag '$out_tag'!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --arg it "$in_tag" --arg ot "$out_tag" \
       '. += [{"inbound": [$it], "outbound": $ot}]' "$ROUTING_FILE" > "$ROUTING_FILE.tmp" && mv "$ROUTING_FILE.tmp" "$ROUTING_FILE"

    log_success "Đã thêm quy tắc định tuyến: Inbound [$in_tag] -> Outbound [$out_tag] thành công!"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi
    
    read -p "Nhấn Enter để tiếp tục..."
}

# Sửa quy tắc định tuyến
edit_routing_rule() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} SỬA QUY TẮC ĐỊNH TUYẾN${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$ROUTING_FILE" ] || [ "$(jq length "$ROUTING_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có quy tắc định tuyến nào để sửa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_routing_table
    read -p "Nhập số thứ tự (STT) của quy tắc cần sửa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$ROUTING_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local old_in old_out
    old_in=$(jq -r --argjson i "$idx" '.[$i].inbound | join(", ")' "$ROUTING_FILE")
    old_out=$(jq -r --argjson i "$idx" '.[$i].outbound' "$ROUTING_FILE")

    echo -e "Đang sửa Quy tắc: Inbound [${CYAN}$old_in${NC}] -> Outbound [${CYAN}$old_out${NC}]"
    
    echo -e "${CYAN}Danh sách Inbound Nodes có sẵn:${NC}"
    jq -r '.[] | "- " + .tag' "$NODES_FILE" 2>/dev/null
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Nhập Inbound Tag mới [Mặc định: $old_in]: " new_in
    new_in="${new_in:-$old_in}"

    if [ "$new_in" != "$old_in" ]; then
        local node_exists
        node_exists=$(jq --arg t "$new_in" '[.[] | select(.tag == $t)] | length' "$NODES_FILE")
        if [ "$node_exists" -eq 0 ]; then
            echo -e "${RED}[LỖI] Không tìm thấy Inbound với tag '$new_in'!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    echo -e "${CYAN}Danh sách Outbounds có sẵn:${NC}"
    jq -r '.[] | "- " + .tag' "$OUTBOUND_FILE" 2>/dev/null
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Nhập Outbound Tag mới [Mặc định: $old_out]: " new_out
    new_out="${new_out:-$old_out}"

    if [ "$new_out" != "$old_out" ]; then
        local outbound_exists
        outbound_exists=$(jq --arg t "$new_out" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
        if [ "$outbound_exists" -eq 0 ]; then
            echo -e "${RED}[LỖI] Không tìm thấy Outbound với tag '$new_out'!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    jq --argjson i "$idx" --arg it "$new_in" --arg ot "$new_out" \
       '.[$i] = {"inbound": [$it], "outbound": $ot}' "$ROUTING_FILE" > "$ROUTING_FILE.tmp" && mv "$ROUTING_FILE.tmp" "$ROUTING_FILE"

    log_success "Đã cập nhật quy tắc định tuyến thành công!"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Xóa quy tắc định tuyến
delete_routing_rule() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${RED} XÓA QUY TẮC ĐỊNH TUYẾN${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$ROUTING_FILE" ] || [ "$(jq length "$ROUTING_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có quy tắc định tuyến nào để xóa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_routing_table
    read -p "Nhập số thứ tự (STT) của quy tắc cần xóa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$ROUTING_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local target_in target_out
    target_in=$(jq -r --argjson i "$idx" '.[$idx].inbound | join(", ")' "$ROUTING_FILE")
    target_out=$(jq -r --argjson i "$idx" '.[$idx].outbound' "$ROUTING_FILE")

    read -p "Bạn có chắc chắn muốn xóa quy tắc (Inbound: $target_in -> Outbound: $target_out) không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        jq --argjson i "$idx" 'del(.[$i])' "$ROUTING_FILE" > "$ROUTING_FILE.tmp" && mv "$ROUTING_FILE.tmp" "$ROUTING_FILE"
        log_success "Đã xóa quy tắc định tuyến khỏi hệ thống!"
        
        if declare -f build_and_apply_config > /dev/null; then
            build_and_apply_config
        fi
    else
        echo "Đã hủy thao tác xóa."
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Khởi chạy menu của module
render_routing_menu