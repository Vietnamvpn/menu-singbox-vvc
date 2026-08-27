#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
NODES_FILE="$INSTALL_DIR/data/nodes.json"
USERS_FILE="$INSTALL_DIR/data/users.json"
ENTRY_NODE_FILE="$INSTALL_DIR/data/entry-node.json"
mkdir -p "$INSTALL_DIR/data"

if [ ! -s "$USERS_FILE" ]; then
    echo "[]" > "$USERS_FILE"
fi

if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
else
    echo "Lỗi: Không tìm thấy file utils.sh tại $INSTALL_DIR/modules/"
    exit 1
fi

list_users() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}||${NC}                   ${YELLOW}DANH SÁCH USER HIỆN TẠI${NC}                  ${BLUE}||${NC}"
    echo -e "${BLUE}================================================================${NC}"
    
    if [ ! -s "$USERS_FILE" ] || [ "$(cat "$USERS_FILE")" = "[]" ]; then
        echo -e "${YELLOW}Chưa có user nào được tạo.${NC}"
        echo -e "${CYAN}================================================================${NC}"
        return 1
    else
        if command -v jq &> /dev/null; then
            jq -r 'to_entries[] | "\(.key + 1). User: \(.value.username) │ Tag: \(.value.tag) │ UUID: \(.value.uuid) │ Status: \(.value.status // "active")"' "$USERS_FILE"
        else
            cat "$USERS_FILE"
        fi
    fi
    echo -e "${CYAN}================================================================${NC}"
    return 0
}

generate_node_links_with_entry() {
    local node="$1"
    local uuid="$2"
    local default_server_ip="$3"

    local type=$(echo "$node" | jq -r '.type')
    local tag=$(echo "$node" | jq -r '.tag')
    local original_port=$(echo "$node" | jq -r '.port')

    local matching_entries="[]"
    if [ -f "$ENTRY_NODE_FILE" ]; then
        matching_entries=$(jq -c --arg n_tag "$tag" '[.[] | select(.node_tag == $n_tag)]' "$ENTRY_NODE_FILE")
    fi

    local entry_count=0
    if [ -n "$matching_entries" ] && [ "$matching_entries" != "[]" ]; then
        entry_count=$(echo "$matching_entries" | jq length)
    fi

    if [ "$entry_count" -gt 0 ]; then
        echo "$matching_entries" | jq -c '.[]' | while read -r entry; do
            [ -z "$entry" ] && continue
            local server_ip=$(echo "$entry" | jq -r '.address')
            local port=$(echo "$entry" | jq -r '.port')
            
            local link=""
            case "$type" in
                "vless-reality"|"vless")
                    local sni=$(echo "$node" | jq -r '.sni // .server_name // empty')
                    local public_key=$(echo "$node" | jq -r '.public_key // empty')
                    local short_id=$(echo "$node" | jq -r '.short_id // empty')
                    link=$(generate_vless_reality_link "$tag" "$server_ip" "$port" "$uuid" "$sni" "$public_key" "$short_id")
                    ;;
                "vless-grpc-reality")
                    local sni=$(echo "$node" | jq -r '.sni // .server_name // empty')
                    local public_key=$(echo "$node" | jq -r '.public_key // empty')
                    local short_id=$(echo "$node" | jq -r '.short_id // empty')
                    local service_name=$(echo "$node" | jq -r '.grpc_service // empty')
                    link=$(generate_vless_grpc_reality_link "$tag" "$server_ip" "$port" "$uuid" "$sni" "$public_key" "$short_id" "$service_name")
                    ;;
                "vless-ws-tls")
                    local domain=$(echo "$node" | jq -r '.domain // empty')
                    local ws_path=$(echo "$node" | jq -r '.ws_path // empty')
                    link=$(generate_vless_ws_tls_link "$tag" "$server_ip" "$port" "$uuid" "$domain" "$ws_path")
                    ;;
                "hysteria2")
                    local domain=$(echo "$node" | jq -r '.domain // empty')
                    link=$(generate_hysteria2_link "$tag" "$server_ip" "$port" "$uuid" "$domain")
                    ;;
                "tuic")
                    local domain=$(echo "$node" | jq -r '.domain // empty')
                    local password=$(echo "$node" | jq -r '.password // empty')
                    link=$(generate_tuic_link "$tag" "$server_ip" "$port" "$uuid" "$password" "$domain")
                    ;;
            esac
            
            if [ -n "$link" ]; then
                echo -e "$link"
            fi
        done
    else
        local server_ip="$default_server_ip"
        local port="$original_port"
        
        local link=""
        case "$type" in
            "vless-reality"|"vless")
                local sni=$(echo "$node" | jq -r '.sni // .server_name // empty')
                local public_key=$(echo "$node" | jq -r '.public_key // empty')
                local short_id=$(echo "$node" | jq -r '.short_id // empty')
                link=$(generate_vless_reality_link "$tag" "$server_ip" "$port" "$uuid" "$sni" "$public_key" "$short_id")
                ;;
            "vless-grpc-reality")
                local sni=$(echo "$node" | jq -r '.sni // .server_name // empty')
                local public_key=$(echo "$node" | jq -r '.public_key // empty')
                local short_id=$(echo "$node" | jq -r '.short_id // empty')
                local service_name=$(echo "$node" | jq -r '.grpc_service // empty')
                link=$(generate_vless_grpc_reality_link "$tag" "$server_ip" "$port" "$uuid" "$sni" "$public_key" "$short_id" "$service_name")
                ;;
            "vless-ws-tls")
                local domain=$(echo "$node" | jq -r '.domain // empty')
                local ws_path=$(echo "$node" | jq -r '.ws_path // empty')
                link=$(generate_vless_ws_tls_link "$tag" "$server_ip" "$port" "$uuid" "$domain" "$ws_path")
                ;;
            "hysteria2")
                local domain=$(echo "$node" | jq -r '.domain // empty')
                link=$(generate_hysteria2_link "$tag" "$server_ip" "$port" "$uuid" "$domain")
                ;;
            "tuic")
                local domain=$(echo "$node" | jq -r '.domain // empty')
                local password=$(echo "$node" | jq -r '.password // empty')
                link=$(generate_tuic_link "$tag" "$server_ip" "$port" "$uuid" "$password" "$domain")
                ;;
        esac
        
        if [ -n "$link" ]; then
            echo -e "$link"
        fi
    fi
}

show_user_links() {
    if ! list_users; then
        sleep 2
        return
    fi
    
    read -p " Nhập số thứ tự user muốn xem link, để trống xem tất cả, 0 để hủy: " user_idx
    if [ "$user_idx" = "0" ]; then
        return
    fi

    local nodes_to_show
    if [ -z "$user_idx" ]; then
        nodes_to_show=$(jq -c '.[]' "$NODES_FILE")
    else
        local real_idx=$((user_idx - 1))
        local user_tag
        user_tag=$(jq -r --argjson idx "$real_idx" '.[$idx].tag // empty' "$USERS_FILE")
        local username
        username=$(jq -r --argjson idx "$real_idx" '.[$idx].username // empty' "$USERS_FILE")

        if [ -z "$username" ]; then
            echo -e "${RED}Lỗi: Số thứ tự user không hợp lệ!${NC}"
            sleep 2
            return
        fi

        if [ "$user_tag" = "all" ]; then
            nodes_to_show=$(jq -c '.[]' "$NODES_FILE")
        else
            nodes_to_show=$(jq -c --arg tag "$user_tag" '.[] | select(.tag == $tag)' "$NODES_FILE")
        fi
    fi

    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}||${NC}                   ${YELLOW}LINK KẾT NỐI HỆ THỐNG${NC}                    ${BLUE}||${NC}"
    echo -e "${BLUE}================================================================${NC}"

    if [ -z "$nodes_to_show" ]; then
        echo -e "${YELLOW}Không tìm thấy node nào phù hợp.${NC}"
    else
        local server_ip
        server_ip=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

        # Nếu cụ thể 1 user
        if [ -n "$user_idx" ]; then
            local username
            username=$(jq -r --argjson idx "$((user_idx - 1))" '.[$idx].username' "$USERS_FILE")
            local uuid
            uuid=$(jq -r --argjson idx "$((user_idx - 1))" '.[$idx].uuid' "$USERS_FILE")
            
            echo -e "${BLUE}User: ${GREEN}$username${NC}"
            echo "$nodes_to_show" | while read -r node; do
                [ -z "$node" ] && continue
                generate_node_links_with_entry "$node" "$uuid" "$server_ip"
            done
        else
            # Tất cả user
            jq -c 'to_entries[]' "$USERS_FILE" | while read -r u_entry; do
                local username=$(echo "$u_entry" | jq -r '.value.username')
                local uuid=$(echo "$u_entry" | jq -r '.value.uuid')
                local u_tag=$(echo "$u_entry" | jq -r '.value.tag')
                
                echo -e "${BLUE}--- User: ${GREEN}$username${NC} ---"
                local u_nodes
                if [ "$u_tag" = "all" ]; then
                    u_nodes=$(jq -c '.[]' "$NODES_FILE")
                else
                    u_nodes=$(jq -c --arg tag "$u_tag" '.[] | select(.tag == $tag)' "$NODES_FILE")
                fi
                
                echo "$u_nodes" | while read -r node; do
                    [ -z "$node" ] && continue
                    generate_node_links_with_entry "$node" "$uuid" "$server_ip"
                done
            done
        fi
    fi
    echo -e "${CYAN}================================================================${NC}"
    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
}

add_user() {
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}||${NC}                     ${YELLOW}THÊM USER MỚI${NC}                          ${BLUE}||${NC}"
    echo -e "${BLUE}================================================================${NC}"

    if [ ! -s "$NODES_FILE" ] || [ "$(cat "$NODES_FILE")" = "[]" ]; then
        echo -e "${RED}Lỗi: Chưa có node nào trong hệ thống để gán user!${NC}"
        sleep 2
        return
    fi

    echo -e "${GREEN}Danh sách các giao thức:${NC}"
    local node_list=()
    if command -v jq &> /dev/null; then
        local i=1
        while read -r tag && read -r type; do
            echo -e " ${GREEN}$i.${NC} Tag: $tag (Type: $type)"
            node_list+=("$tag")
            i=$((i + 1))
        done < <(jq -r '.[] | .tag, .type' "$NODES_FILE")
    fi
    echo -e " ${RED}0.${NC} Hủy bỏ / Quay lại"
    echo -e "${CYAN}================================================================${NC}"

    read -p " Nhập số thứ tự node muốn gán, để trống gán tất cả: " node_choice

    if [ "$node_choice" = "0" ]; then
        return
    fi

    local target_tag="all"
    if [ -n "$node_choice" ]; then
        local idx=$((node_choice - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#node_list[@]} ]; then
            target_tag="${node_list[$idx]}"
        else
            echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            sleep 2
            return
        fi
    fi

    read -p " Nhập tên User, 0 để hủy: " username
    if [ "$username" = "0" ] || [ -z "$username" ]; then
        return
    fi

    if grep -q "\"username\": \"$username\"" "$USERS_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Username '$username' đã tồn tại!${NC}"
        sleep 2
        return
    fi

    local uuid=""
    if command -v uuidgen >/dev/null 2>&1; then
        uuid=$(uuidgen)
    else
        uuid=$(cat /proc/sys/kernel/random/uuid)
    fi
    echo -e "${GREEN} -> Đã tự động tạo UUID cho user: $uuid${NC}"

    if jq --arg username "$username" \
       --arg tag "$target_tag" \
       --arg uuid "$uuid" \
       '. += [{
           "username": $username,
           "tag": $tag,
           "uuid": $uuid,
           "status": "active"
       }]' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"; then
        echo -e "${GREEN}Thêm User thành công!${NC}"
        build_and_apply_config
    else
        echo -e "${RED}Lỗi: Không thể ghi dữ liệu vào tệp users.json!${NC}"
    fi
    sleep 2
}

delete_user() {
    clear
    if ! list_users; then
        sleep 2
        return
    fi
    
    read -p " Nhập số thứ tự user cần xóa, để trống xóa tất cả, 0 để hủy: " user_choice
    if [ "$user_choice" = "0" ]; then
        return
    fi

    if command -v jq &> /dev/null; then
        if [ -z "$user_choice" ]; then
            echo "[]" > "$USERS_FILE"
            echo -e "${GREEN}Đã xóa tất cả user!${NC}"
        else
            local indices=()
            for idx in $user_choice; do
                if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -gt 0 ]; then
                    indices+=($((idx - 1)))
                fi
            done
            
            if [ ${#indices[@]} -eq 0 ]; then
                echo -e "${RED}Lỗi: Số thứ tự không hợp lệ!${NC}"
                sleep 2
                return
            fi
            
            local jq_filter="del(.[$(IFS=','; echo "${indices[*]}")] )"
            jq "$jq_filter" "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
            echo -e "${GREEN}Đã xóa các user được chọn!${NC}"
        fi
        build_and_apply_config
    else
        echo -e "${RED}Thiếu công cụ jq để xử lý JSON.${NC}"
    fi
    sleep 2
}

reset_user_token() {
    clear
    if ! list_users; then
        sleep 2
        return
    fi
    
    read -p " Nhập số thứ tự user cần reset token, để trống reset tất cả, 0 để hủy: " user_choice
    if [ "$user_choice" = "0" ]; then
        return
    fi

    if command -v jq &> /dev/null; then
        local new_uuid=""
        if command -v uuidgen >/dev/null 2>&1; then
            new_uuid=$(uuidgen)
        else
            new_uuid=$(cat /proc/sys/kernel/random/uuid)
        fi

        if [ -z "$user_choice" ]; then
            jq --arg uuid "$new_uuid" '[.[] | .uuid = $uuid]' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
            echo -e "${GREEN}Đã reset token thành công cho tất cả user!${NC}"
        else
            local real_idx=$((user_choice - 1))
            local username
            username=$(jq -r --argjson idx "$real_idx" '.[$idx].username // empty' "$USERS_FILE")

            if [ -z "$username" ]; then
                echo -e "${RED}Lỗi: Số thứ tự user không hợp lệ!${NC}"
                sleep 2
                return
            fi
            
            jq --arg username "$username" \
               --arg uuid "$new_uuid" \
               '(.[] | select(.username == $username).uuid) = $uuid' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
            echo -e "${GREEN}Đã reset token thành công cho user: $username${NC}"
            echo -e "${GREEN}Token mới: $new_uuid${NC}"
        fi
        build_and_apply_config
    else
        echo -e "${RED}Thiếu công cụ jq để xử lý JSON.${NC}"
    fi
    sleep 2
}

while true; do
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}||${NC}                   ${YELLOW}QUẢN LÝ THÔNG TIN USER${NC}                   ${BLUE}||${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e " ${GREEN}1.${NC} Xem Danh Sách User & Link"
    echo -e " ${GREEN}2.${NC} Thêm User Mới"
    echo -e " ${GREEN}3.${NC} Xóa User"
    echo -e " ${GREEN}4.${NC} Reset Token User"
    echo -e " ${RED}0.${NC} Quay Lại Menu Chính"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn chức năng [0-4]: " choice

    case $choice in
        1)
            show_user_links
            ;;
        2)
            add_user
            ;;
        3)
            delete_user
            ;;
        4)
            reset_user_token
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            sleep 1
            ;;
    esac
done