#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
NODES_FILE="$INSTALL_DIR/data/nodes.json"
USERS_FILE="$INSTALL_DIR/data/users.json"
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
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                    DANH SÁCH USER HIỆN TẠI                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    
    if [ ! -s "$USERS_FILE" ] || [ "$(cat "$USERS_FILE")" = "[]" ]; then
        echo -e "${YELLOW}Chưa có user nào được tạo.${NC}"
        echo -e "${CYAN}================================================================${NC}"
        return 1
    else
        if command -v jq &> /dev/null; then
            jq -r 'to_entries[] | "\(.key + 1). User: \(.value.username) │ Pass/UUID: \(.value.secret)"' "$USERS_FILE"
        else
            cat "$USERS_FILE"
        fi
    fi
    echo -e "${CYAN}================================================================${NC}"
    return 0
}

show_user_links() {
    if ! list_users; then
        sleep 2
        return
    fi
    
    read -p " Nhập số thứ tự user muốn xem link (hoặc để trống để quay lại): " user_idx
    if [ -z "$user_idx" ]; then
        return
    fi

    local real_idx=$((user_idx - 1))
    local username
    local secret
    local user_tag
    
    username=$(jq -r --argjson idx "$real_idx" '.[$idx].username // empty' "$USERS_FILE")
    secret=$(jq -r --argjson idx "$real_idx" '.[$idx].secret // empty' "$USERS_FILE")
    user_tag=$(jq -r --argjson idx "$real_idx" '.[$idx].tag // empty' "$USERS_FILE")

    if [ -z "$username" ]; then
        echo -e "${RED}Lỗi: Số thứ tự user không hợp lệ!${NC}"
        sleep 2
        return
    fi

    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}           LINK KẾT NỐI CHO USER: ${GREEN}$username${NC}"
    echo -e "${CYAN}================================================================${NC}"

    local nodes_to_show
    if [ "$user_tag" = "all" ]; then
        nodes_to_show=$(jq -c '.[]' "$NODES_FILE")
    else
        nodes_to_show=$(jq -c --arg tag "$user_tag" '.[] | select(.tag == $tag)' "$NODES_FILE")
    fi

    if [ -z "$nodes_to_show" ]; then
        echo -e "${YELLOW}Không tìm thấy node nào phù hợp cho user này.${NC}"
    else
        local server_ip
        server_ip=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

        echo "$nodes_to_show" | while read -r node; do
            local type=$(echo "$node" | jq -r '.type')
            local tag=$(echo "$node" | jq -r '.tag')
            local port=$(echo "$node" | jq -r '.port')
            
            if [ "$type" = "vless-reality" ] || [ "$type" = "vless" ]; then
                local sni=$(echo "$node" | jq -r '.sni // .server_name')
                local public_key=$(echo "$node" | jq -r '.public_key // empty')
                local short_id=$(echo "$node" | jq -r '.short_id // empty')
                
                local link
                link=$(generate_vless_reality_link "$tag" "$server_ip" "$port" "$secret" "$sni" "$public_key" "$short_id")
                echo -e "${GREEN}Node (${tag}):${NC}"
                echo -e "$link\n"
            else
                echo -e "${YELLOW}Node (${tag}) - Loại ${type} chưa hỗ trợ hiển thị link tự động.${NC}"
            fi
        done
    fi
    echo -e "${CYAN}================================================================${NC}"
    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
}

add_user() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                     THÊM USER MỚI                             ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    
    if [ ! -s "$NODES_FILE" ] || [ "$(cat "$NODES_FILE")" = "[]" ]; then
        echo -e "${RED}Lỗi: Chưa có node nào trong hệ thống để gán user!${NC}"
        sleep 2
        return
    fi

    echo -e "${GREEN}Danh sách các giao thức/node hiện có:${NC}"
    local node_list=()
    if command -v jq &> /dev/null; then
        local i=1
        while read -r tag && read -r type; do
            echo -e " ${GREEN}$i.${NC} Tag: $tag (Type: $type)"
            node_list+=("$tag")
            i=$((i + 1))
        done < <(jq -r '.[] | .tag, .type' "$NODES_FILE")
    fi
    echo -e " ${GREEN}0.${NC} Gán vào tất cả các node"
    echo -e "${CYAN}================================================================${NC}"

    read -p " Nhập số thứ tự node muốn gán (để trống hoặc nhập 0 để gán tất cả): " node_choice

    local target_tag="all"
    if [ -n "$node_choice" ] && [ "$node_choice" -ne 0 ]; then
        local idx=$((node_choice - 1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#node_list[@]} ]; then
            target_tag="${node_list[$idx]}"
        else
            echo -e "${RED}Lựa chọn không hợp lệ, mặc định gán vào tất cả các node!${NC}"
            target_tag="all"
            sleep 2
        fi
    fi

    read -p " Nhập tên User (Username): " username
    if [ -z "$username" ]; then
        echo -e "${RED}Lỗi: Username không được để trống!${NC}"
        sleep 2
        return
    fi

    if grep -q "\"username\": \"$username\"" "$USERS_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Username '$username' đã tồn tại!${NC}"
        sleep 2
        return
    fi

    local secret=""
    if command -v uuidgen >/dev/null 2>&1; then
        secret=$(uuidgen)
    else
        secret=$(cat /proc/sys/kernel/random/uuid)
    fi
    echo -e "${GREEN} -> Đã tự động tạo UUID cho user: $secret${NC}"

    if jq --arg username "$username" \
       --arg tag "$target_tag" \
       --arg secret "$secret" \
       '. += [{
           "username": $username,
           "tag": $tag,
           "secret": $secret
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
    list_users
    read -p " Nhập username của user cần xóa: " username
    if [ -z "$username" ]; then return; fi

    if command -v jq &> /dev/null; then
        jq --arg username "$username" '[.[] | select(.username != $username)]' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"
        echo -e "${GREEN}Đã xóa user: $username${NC}"
        build_and_apply_config
    else
        echo -e "${RED}Thiếu công cụ jq để xử lý JSON.${NC}"
    fi
    sleep 2
}

reset_user_token() {
    clear
    list_users
    read -p " Nhập username của user cần reset token: " username
    if [ -z "$username" ]; then return; fi

    if ! grep -q "\"username\": \"$username\"" "$USERS_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Không tìm thấy user '$username'!${NC}"
        sleep 2
        return
    fi

    local new_secret=""
    if command -v uuidgen >/dev/null 2>&1; then
        new_secret=$(uuidgen)
    else
        new_secret=$(cat /proc/sys/kernel/random/uuid)
    fi
    
    if jq --arg username "$username" \
       --arg secret "$new_secret" \
       '(.[] | select(.username == $username).secret) = $secret' "$USERS_FILE" > "$USERS_FILE.tmp" && mv "$USERS_FILE.tmp" "$USERS_FILE"; then
        echo -e "${GREEN}Đã reset token thành công cho user: $username${NC}"
        echo -e "${GREEN}Token mới: $new_secret${NC}"
        build_and_apply_config
    else
        echo -e "${RED}Lỗi: Không thể cập nhật token trong tệp users.json!${NC}"
    fi
    sleep 2
}

while true; do
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                     QUẢN LÝ THÔNG TIN USER                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e " ${GREEN}1.${NC} Hiển thị danh sách User & Xem Link"
    echo -e " ${GREEN}2.${NC} Thêm User mới"
    echo -e " ${GREEN}3.${NC} Xóa User"
    echo -e " ${GREEN}4.${NC} Reset Token User"
    echo -e "${RED}0.${NC} Quay lại Menu chính"
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