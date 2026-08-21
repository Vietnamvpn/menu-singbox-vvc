#!/bin/bash

# ==========================================
# Main Menu Script cho menu-singbox-vvc
# ==========================================

INSTALL_DIR="/opt/menu-singbox-vvc"

# Nạp các hàm dùng chung từ modules/utils.sh
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
else
    echo -e "\033[0;31m[ERROR]\033[0m Không tìm thấy tệp modules/utils.sh!"
    exit 1
fi

VERSION="v1.0.0"
AUTHOR="Vietnamvpn"
WEBSITE="https://github.com/Vietnamvpn"

# Hàm hiển thị Banner và Lời chào
show_banner() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${PURPLE}   ___ _             ___             __  __                     ${NC}"
    echo -e "${PURPLE}  / __(_)_ _  __ _  | _ ) _____ __  |  \/  |__ _ _ _  __ _ __ _ ${NC}"
    echo -e "${PURPLE}  \__ \ | ' \/ _\` | | _ \/ _ \ \ /  | |\/| / _\` | ' \\/ _\` / _\` |${NC}"
    echo -e "${PURPLE}  |___/_|_||_\__, | |___/\___/_\_\  |_|  |_\\__,_|_||_\\__,_\__, |${NC}"
    echo -e "${PURPLE}             |___/                                        |___/ ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE} Xin chào! Chào mừng bạn đến với hệ thống quản lý Sing-box VVC${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e " ${YELLOW}Tác giả:${NC} $AUTHOR"
    echo -e " ${YELLOW}Website/Git:${NC} $WEBSITE"
    echo -e " ${YELLOW}Phiên bản Script:${NC} $VERSION"
    echo -e " ${YELLOW}Phiên bản Core:${NC} $(get_singbox_version)"
    echo -e " ${YELLOW}Trạng thái Core:${NC} $(get_singbox_status)"
    echo -e "${CYAN}================================================================${NC}"
}

# Menu con: Quản lý Node (Chỉ hiện khi bấm vào Quản lý Node ở menu chính)
show_node_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================================${NC}"
        echo -e "${PURPLE}                      QUẢN LÝ NODE & ROUTING                    ${NC}"
        echo -e "${CYAN}================================================================${NC}"
        echo -e "${GREEN} 1.${NC} Hiển thị & Quản lý Node"
        echo -e "${GREEN} 2.${NC} Thêm Node"
        echo -e "${GREEN} 3.${NC} Thêm Entry"
        echo -e "${GREEN} 4.${NC} Thêm Outbound"
        echo -e "${GREEN} 5.${NC} Thêm Routing"
        echo -e "${GREEN} 0.${NC} Quay lại Menu Chính"
        echo -e "${CYAN}================================================================${NC}"
        read -p " Vui lòng chọn chức năng [0-5]: " sub_choice

        case $sub_choice in
            1|2)
                log_info "Đang mở Quản lý Node..."
                if [ -f "$INSTALL_DIR/modules/nodes.sh" ]; then
                    bash "$INSTALL_DIR/modules/nodes.sh"
                else
                    log_warn "Chưa có module nodes.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            3)
                log_info "Đang mở Quản lý Entry Node..."
                if [ -f "$INSTALL_DIR/modules/entry-node.sh" ]; then
                    bash "$INSTALL_DIR/modules/entry-node.sh"
                else
                    log_warn "Chưa có module entry-node.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            4)
                log_info "Đang mở Quản lý Node Relay (Outbound)..."
                if [ -f "$INSTALL_DIR/modules/outbound.sh" ]; then
                    bash "$INSTALL_DIR/modules/outbound.sh"
                else
                    log_warn "Chưa có module outbound.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            5)
                log_info "Đang mở Cấu hình Định tuyến (Routing)..."
                if [ -f "$INSTALL_DIR/modules/routing.sh" ]; then
                    bash "$INSTALL_DIR/modules/routing.sh"
                else
                    log_warn "Chưa có module routing.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Lựa chọn không hợp lệ, vui lòng thử lại!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Hàm Menu chính
show_menu() {
    show_banner
    echo -e "${GREEN} 1.${NC} Quản lý Node"
    echo -e "${GREEN} 2.${NC} Quản lý Người dùng (Users)"
    echo -e "${GREEN} 3.${NC} Quản lý Chứng chỉ SSL"
    echo -e "${GREEN} 4.${NC} Quản lý Hệ thống & Service (System)"
    echo -e "${GREEN} 5.${NC} API Web Trung tâm"
    echo -e "${GREEN} 6.${NC} Cập nhật hệ thống (Update Script)"
    echo -e "${GREEN} 0.${NC} Thoát"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn một chức năng [0-6]: " choice

    case $choice in
        1)
            show_node_menu
            show_menu
            ;;
        2)
            log_info "Đang mở Quản lý Người dùng..."
            if [ -f "$INSTALL_DIR/modules/users.sh" ]; then
                bash "$INSTALL_DIR/modules/users.sh"
            else
                log_warn "Chưa có module users.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            show_menu
            ;;
        3)
            log_info "Đang mở Quản lý SSL..."
            if [ -f "$INSTALL_DIR/modules/ssl.sh" ]; then
                bash "$INSTALL_DIR/modules/ssl.sh"
            else
                log_warn "Chưa có module ssl.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            show_menu
            ;;
        4)
            log_info "Đang mở Quản lý Hệ thống & Service..."
            if [ -f "$INSTALL_DIR/modules/system.sh" ]; then
                bash "$INSTALL_DIR/modules/system.sh"
            else
                log_warn "Chưa có module system.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            show_menu
            ;;
        5)
            log_info "Đang mở API Web Trung tâm..."
            if [ -f "$INSTALL_DIR/modules/api-web.sh" ]; then
                bash "$INSTALL_DIR/modules/api-web.sh"
            else
                log_warn "Chưa có module api-web.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            show_menu
            ;;
        6)
            if [ -f "$INSTALL_DIR/update.sh" ]; then
                bash "$INSTALL_DIR/update.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            else
                log_error "Không tìm thấy file update.sh!"
            fi
            show_menu
            ;;
        0)
            echo -e "${BLUE}Cảm ơn bạn đã sử dụng VVC. Hẹn gặp lại!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ, vui lòng thử lại!${NC}"
            sleep 2
            show_menu
            ;;
    esac
}

# Vòng lặp chính
while true; do
    show_menu
done