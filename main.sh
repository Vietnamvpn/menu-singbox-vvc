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
WEBSITE="https://linksub24h.com"

# Hàm hiển thị Banner và Lời chào gọn gàng
show_banner() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${PURPLE}                    MENU-SINGBOX-VVC                          ${NC}"
    echo -e "${YELLOW}                 Phiên bản:${NC} $VERSION" 
    echo -e "${CYAN}================================================================${NC}"
    echo -e " ${YELLOW}Tác giả:${NC} $AUTHOR | ${YELLOW}Website:${NC} $WEBSITE" 
    echo -e " ${YELLOW}Core Ver:${NC}  $(get_singbox_version) | ${YELLOW}Trạng thái:${NC}  $(get_singbox_status)"
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
                clear
                log_info "Đang mở Quản lý Node..."
                if [ -f "$INSTALL_DIR/modules/nodes.sh" ]; then
                    bash "$INSTALL_DIR/modules/nodes.sh"
                else
                    log_warn "Chưa có module nodes.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            3)
                clear
                log_info "Đang mở Quản lý Entry Node..."
                if [ -f "$INSTALL_DIR/modules/entry-node.sh" ]; then
                    bash "$INSTALL_DIR/modules/entry-node.sh"
                else
                    log_warn "Chưa có module entry-node.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            4)
                clear
                log_info "Đang mở Quản lý Node Relay (Outbound)..."
                if [ -f "$INSTALL_DIR/modules/outbound.sh" ]; then
                    bash "$INSTALL_DIR/modules/outbound.sh"
                else
                    log_warn "Chưa có module outbound.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
                ;;
            5)
                clear
                log_info "Đang mở Cấu hình Định tuyến (Routing)..."
                if [ -f "$INSTALL_DIR/modules/routing.sh" ]; then
                    bash "$INSTALL_DIR/modules/routing.sh"
                else
                    log_warn "Chưa có module routing.sh"
                    read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
                fi
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
}

# Hàm Menu chính
show_menu() {
    clear
    show_banner
    echo -e "${GREEN} 1.${NC} Quản lý Node"
    echo -e "${GREEN} 2.${NC} Quản lý Người dùng (Users)"
    echo -e "${GREEN} 3.${NC} Quản lý Chứng chỉ SSL"
    echo -e "${GREEN} 4.${NC} Quản lý Hệ thống & Service (System)"
    echo -e "${GREEN} 5.${NC} API Web Trung tâm"
    echo -e "${GREEN} 6.${NC} Kích hoạt TCP BBR"
    echo -e "${GREEN} 7.${NC} Thêm bộ nhớ Swap"
    echo -e "${GREEN} 8.${NC} Cập nhật hệ thống (Update Script)"
    echo -e "${GREEN} 9.${NC} Gỡ bỏ hoàn toàn hệ thống (Uninstall)"
    echo -e "${GREEN} 0.${NC} Thoát"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn một chức năng [0-9]: " choice

    case $choice in
        1)
            show_node_menu
            ;;
        2)
            clear
            log_info "Đang mở Quản lý Người dùng..."
            if [ -f "$INSTALL_DIR/modules/users.sh" ]; then
                bash "$INSTALL_DIR/modules/users.sh"
            else
                log_warn "Chưa có module users.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            ;;
        3)
            clear
            log_info "Đang mở Quản lý SSL..."
            if [ -f "$INSTALL_DIR/modules/ssl.sh" ]; then
                bash "$INSTALL_DIR/modules/ssl.sh"
            else
                log_warn "Chưa có module ssl.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            ;;
        4)
            clear
            log_info "Đang mở Quản lý Hệ thống & Service..."
            if [ -f "$INSTALL_DIR/modules/system.sh" ]; then
                bash "$INSTALL_DIR/modules/system.sh"
            else
                log_warn "Chưa có module system.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            ;;
        5)
            clear
            log_info "Đang mở API Web Trung tâm..."
            if [ -f "$INSTALL_DIR/modules/api-web.sh" ]; then
                bash "$INSTALL_DIR/modules/api-web.sh"
            else
                log_warn "Chưa có module api-web.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để quay lại..."
            fi
            ;;
        6)
            clear
            enable_bbr
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        7)
            clear
            read -p "Nhập dung lượng Swap muốn tạo (Ví dụ: 2G, 1G) [Mặc định 2G]: " swap_input
            add_swap "${swap_input:-2G}"
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        8)
            clear
            if [ -f "$INSTALL_DIR/update.sh" ]; then
                bash "$INSTALL_DIR/update.sh"
                read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            else
                log_error "Không tìm thấy file update.sh!"
            fi
            ;;
        9)
            clear
            uninstall_system
            ;;
        0)
            clear
            echo -e "${BLUE}Cảm ơn bạn đã sử dụng VVC. Hẹn gặp lại!${NC}"
            exit 0
            ;;
        *)
            clear
            echo -e "${RED}Lựa chọn không hợp lệ, vui lòng thử lại!${NC}"
            sleep 2
            ;;
    esac
}

# Vòng lặp chính
while true; do
    show_menu
done