#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
fi

ENTRY_NODE_FILE="${INSTALL_DIR}/data/entry-node.json"

mkdir -p "$(dirname "$ENTRY_NODE_FILE")"
[ ! -f "$ENTRY_NODE_FILE" ] && echo "[]" > "$ENTRY_NODE_FILE"

# Menu quản lý Entry Node
render_entry_node_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${BLUE}||${NC}                  ${YELLOW}QUẢN LÝ ENTRY NODE (CẤP LINK)           ${BLUE}||${NC}"
        echo -e "${BLUE}================================================================${NC}"
        list_entry_nodes_table
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Entry Node"
        echo -e " ${GREEN}2.${NC} Sửa Entry Node"
        echo -e " ${GREEN}3.${NC} Xóa Entry Node"
        echo -e "${RED}0.${NC} Quay lại Menu Chính"
        echo -e "${BLUE}================================================================${NC}"
        read -p " Vui lòng chọn một chức năng [0-3]: " choice

        case "$choice" in
            1)
                add_entry_node
                ;;
            2)
                edit_entry_node
                ;;
            3)
                delete_entry_node
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

# Hiển thị bảng danh sách entry node
list_entry_nodes_table() {
    echo -e " ${CYAN}Danh sách Entry Node hiện tại:${NC}"
    if [ ! -s "$ENTRY_NODE_FILE" ] || [ "$(jq length "$ENTRY_NODE_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e " ${YELLOW}(Chưa có entry node nào được cấu hình)${NC}"
        return
    fi
    
    echo -e "${CYAN}----------------------------------------------------------------------------------------${NC}"
    printf "${CYAN}%-4s${NC} | ${GREEN}%-18s${NC} | ${YELLOW}%-20s${NC} | ${BLUE}%-6s${NC} | ${PURPLE}%-20s${NC}\n" "STT" "Tên Entry" "Địa chỉ (IP/Domain)" "Cổng" "Liên kết Node"
    echo -e "${CYAN}----------------------------------------------------------------------------------------${NC}"
    
    local count
    count=$(jq length "$ENTRY_NODE_FILE")
    for ((i=0; i<count; i++)); do
        local tag address port node_tag
        tag=$(jq -r --argjson idx "$i" '.[$idx].tag // "N/A"' "$ENTRY_NODE_FILE")
        address=$(jq -r --argjson idx "$i" '.[$idx].address // "N/A"' "$ENTRY_NODE_FILE")
        port=$(jq -r --argjson idx "$i" '.[$idx].port // "N/A"' "$ENTRY_NODE_FILE")
        node_tag=$(jq -r --argjson idx "$i" '.[$idx].node_tag // "N/A"' "$ENTRY_NODE_FILE")
        printf "%-4d | %-18s | %-20s | %-6s | %-20s\n" "$((i+1))" "$tag" "$address" "$port" "$node_tag"
    done
    echo -e "${CYAN}----------------------------------------------------------------------------------------${NC}"
}

# Thêm entry node mới
add_entry_node() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} THÊM ENTRY NODE${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    local nodes_file="${INSTALL_DIR}/data/nodes.json"
    if [ ! -s "$nodes_file" ] || [ "$(jq length "$nodes_file" 2>/dev/null)" -eq 0 ]; then
        echo -e "${RED}[LỖI] Chưa có Node (Inbound) nào trong hệ thống! Vui lòng tạo node trước.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    echo -e "${CYAN}Danh sách Node (Inbound) hiện có:${NC}"
    jq -r '.[] | " - Tag: \(.tag) [Loại: \(.type)]"' "$nodes_file"
    echo -e "${CYAN}--------------------------------------------------${NC}"

    read -p "Nhập Tên / Tag định danh cho Entry Node (vd: entry-us-1): " tag
    if [ -z "$tag" ]; then
        echo -e "${RED}[LỖI] Tên / Tag không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local exists
    exists=$(jq --arg t "$tag" '[.[] | select(.tag == $t)] | length' "$ENTRY_NODE_FILE")
    if [ "$exists" -gt 0 ]; then
        echo -e "${RED}[LỖI] Tag '$tag' đã tồn tại! Vui lòng chọn tên khác.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Tag của Node cần liên kết (Node Tag tương ứng): " node_tag
    if [ -z "$node_tag" ]; then
        echo -e "${RED}[LỖI] Node Tag không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local node_exists
    node_exists=$(jq --arg nt "$node_tag" '[.[] | select(.tag == $nt)] | length' "$nodes_file")
    if [ "$node_exists" -eq 0 ]; then
        echo -e "${RED}[LỖI] Node Tag '$node_tag' không tồn tại trong hệ thống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Domain hoặc Địa chỉ IP của Entry Node: " address
    if [ -z "$address" ]; then
        echo -e "${RED}[LỖI] Địa chỉ không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Cổng (Port) của Entry Node: " port
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] Cổng (Port) phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --arg t "$tag" --arg addr "$address" --argjson p "$port" --arg nt "$node_tag" \
       '. += [{"tag": $t, "address": $addr, "port": $p, "node_tag": $nt}]' "$ENTRY_NODE_FILE" > "$ENTRY_NODE_FILE.tmp" && mv "$ENTRY_NODE_FILE.tmp" "$ENTRY_NODE_FILE"

    log_success "Đã thêm entry node '$tag' liên kết với node '$node_tag' thành công!"
    read -p "Nhấn Enter để tiếp tục..."
}

# Sửa entry node
edit_entry_node() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} SỬA ENTRY NODE${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$ENTRY_NODE_FILE" ] || [ "$(jq length "$ENTRY_NODE_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có entry node nào để sửa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_entry_nodes_table
    read -p "Nhập số thứ tự (STT) của entry node cần sửa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$ENTRY_NODE_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local old_tag old_address old_port old_node_tag
    old_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$ENTRY_NODE_FILE")
    old_address=$(jq -r --argjson i "$idx" '.[$i].address' "$ENTRY_NODE_FILE")
    old_port=$(jq -r --argjson i "$idx" '.[$i].port' "$ENTRY_NODE_FILE")
    old_node_tag=$(jq -r --argjson i "$idx" '.[$i].node_tag // ""' "$ENTRY_NODE_FILE")

    echo -e "Đang sửa Entry Node: ${CYAN}$old_tag${NC}"
    
    read -p "Nhập Tag mới [Mặc định: $old_tag]: " new_tag
    new_tag="${new_tag:-$old_tag}"

    if [ "$new_tag" != "$old_tag" ]; then
        local exists
        exists=$(jq --arg t "$new_tag" '[.[] | select(.tag == $t)] | length' "$ENTRY_NODE_FILE")
        if [ "$exists" -gt 0 ]; then
            echo -e "${RED}[LỖI] Tag '$new_tag' đã bị trùng với entry node khác!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    local nodes_file="${INSTALL_DIR}/data/nodes.json"
    echo -e "${CYAN}Danh sách Node (Inbound) hiện có:${NC}"
    if [ -f "$nodes_file" ]; then
        jq -r '.[] | " - Tag: \(.tag) [Loại: \(.type)]"' "$nodes_file"
    fi
    echo -e "${CYAN}--------------------------------------------------${NC}"

    read -p "Nhập Node Tag liên kết mới [Mặc định: $old_node_tag]: " new_node_tag
    new_node_tag="${new_node_tag:-$old_node_tag}"

    if [ -n "$new_node_tag" ] && [ -f "$nodes_file" ]; then
        local node_exists
        node_exists=$(jq --arg nt "$new_node_tag" '[.[] | select(.tag == $nt)] | length' "$nodes_file")
        if [ "$node_exists" -eq 0 ]; then
            echo -e "${RED}[LỖI] Node Tag '$new_node_tag' không tồn tại trong hệ thống!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    read -p "Nhập Địa chỉ mới (IP/Domain) [Mặc định: $old_address]: " new_address
    new_address="${new_address:-$old_address}"

    read -p "Nhập Cổng mới [Mặc định: $old_port]: " new_port
    new_port="${new_port:-$old_port}"

    if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] Cổng (Port) phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --argjson i "$idx" --arg t "$new_tag" --arg addr "$new_address" --argjson p "$new_port" --arg nt "$new_node_tag" \
       '.[$i] = {"tag": $t, "address": $addr, "port": $p, "node_tag": $nt}' "$ENTRY_NODE_FILE" > "$ENTRY_NODE_FILE.tmp" && mv "$ENTRY_NODE_FILE.tmp" "$ENTRY_NODE_FILE"

    log_success "Đã cập nhật entry node thành công!"
    read -p "Nhấn Enter để tiếp tục..."
}

# Xóa entry node
delete_entry_node() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${RED} XÓA ENTRY NODE${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$ENTRY_NODE_FILE" ] || [ "$(jq length "$ENTRY_NODE_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có entry node nào để xóa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_entry_nodes_table
    read -p "Nhập số thứ tự (STT) của entry node cần xóa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$ENTRY_NODE_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local target_tag
    target_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$ENTRY_NODE_FILE")

    read -p "Bạn có chắc chắn muốn xóa entry node '$target_tag' không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        jq --argjson i "$idx" 'del(.[$i])' "$ENTRY_NODE_FILE" > "$ENTRY_NODE_FILE.tmp" && mv "$ENTRY_NODE_FILE.tmp" "$ENTRY_NODE_FILE"
        log_success "Đã xóa entry node '$target_tag' khỏi hệ thống!"
    else
        echo "Đã hủy thao tác xóa."
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Khởi chạy menu của module
render_entry_node_menu