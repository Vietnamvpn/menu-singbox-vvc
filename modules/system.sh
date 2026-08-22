#!/bin/bash

# ==========================================
# modules/system.sh - Điều khiển Sing-box Core
# ==========================================

INSTALL_DIR="/opt/menu-singbox-vvc"

if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
else
    echo -e "\033[0;31m[ERROR]\033[0m Không tìm thấy tệp modules/utils.sh!"
    exit 1
fi

while true; do
    clear
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}||${NC}                 ${YELLOW}ĐIỀU KHIỂN SING-BOX CORE${NC}               ${BLUE}||${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo -e " ${YELLOW}Trạng thái Core:${NC} $(get_singbox_status)  │  ${YELLOW}Phiên bản:${NC} $(get_singbox_version)"
    echo -e "${BLUE}================================================================${NC}"
    echo -e " ${GREEN}1.${NC} Khởi Động Sing-box"
    echo -e " ${GREEN}2.${NC} Dừng Sing-box"
    echo -e " ${GREEN}3.${NC} Khởi Động Lại Sing-box"
    echo -e " ${GREEN}4.${NC} Cập Nhật Sing-box Core Mới Nhất"
    echo -e "${RED}0.${NC} Quay Lại Menu Chính"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn chức năng [0-4]: " choice

    case $choice in
        1)
            clear
            start_singbox #[cite: 9]
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        2)
            clear
            stop_singbox #[cite: 9]
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        3)
            clear
            restart_singbox #[cite: 9]
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        4)
            clear
            update_singbox_core #[cite: 9]
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        0)
            clear
            break
            ;;
        *)
            clear
            echo -e "${RED}Lựa chọn không hợp lệ, vui lòng thử lại!${NC}"
            sleep 1
            ;;
    esac
done