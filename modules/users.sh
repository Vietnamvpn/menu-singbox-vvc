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
    else
        if command -v jq &> /dev/null; then
            jq -r '.[] | "User: \(.username) │ Node Tag: \(.tag) │ Pass/UUID: \(.secret)"' "$USERS_FILE"
        else
            cat "$USERS_FILE"
        fi
    fi
    echo -e "${CYAN}================================================================${NC}"
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

    if command -v jq &> /dev/null; then
        echo -e "${GREEN}Các Node hiện có:${NC}"
        jq -r '.[] | " - Tag: \(.tag) (Type: \(.type))"' "$NODES_FILE"
    fi

    read -p " Nhập Tag của node muốn thêm user: " target_tag
    if [ -z "$target_tag" ]; then return; fi

    if ! grep -q "\"tag\": \"$target_tag\"" "$NODES_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Không tìm thấy node với tag '$target_tag'!${NC}"
        sleep 2
        return
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

    local secret=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)
    echo -e "${GREEN} -> Đã tự động tạo secret cho user: $secret${NC}"

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

while true; do
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                     QUẢN LÝ THÔNG TIN USER                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e " ${GREEN}1.${NC} Hiển thị danh sách User"
    echo -e " ${GREEN}2.${NC} Thêm User mới"
    echo -e " ${GREEN}3.${NC} Xóa User"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn chức năng [0-3]: " choice

    case $choice in
        1)
            list_users
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        2)
            add_user
            ;;
        3)
            delete_user
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