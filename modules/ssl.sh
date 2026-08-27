#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
fi

CERT_DIR="/etc/sing-box/certs"
mkdir -p "$CERT_DIR"

# Menu quản lý SSL
render_ssl_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${BLUE}||${NC}             ${YELLOW}QUẢN LÝ CHỨNG CHỈ SSL (CLOUDFLARE)             ${BLUE}||${NC}"
        echo -e "${BLUE}================================================================${NC}"
        view_ssl_info_summary
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${GREEN}1.${NC} Xin / Cập nhật chứng chỉ SSL (Cloudflare DNS API)"
        echo -e " ${GREEN}2.${NC} Xem chi tiết chứng chỉ hiện tại"
        echo -e " ${GREEN}3.${NC} Gỡ bỏ chứng chỉ SSL"
        echo -e " ${RED}0.${NC} Quay lại Menu Chính"
        echo -e "${BLUE}================================================================${NC}"
        read -p " Vui lòng chọn một chức năng [0-3]: " choice

        case "$choice" in
            1)
                request_cloudflare_ssl
                ;;
            2)
                view_ssl_details
                ;;
            3)
                remove_ssl
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

# Tóm tắt nhanh trạng thái SSL trên menu
view_ssl_info_summary() {
    echo -e " ${CYAN}Trạng thái chứng chỉ SSL hiện tại:${NC}"
    if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/private.key" ]; then
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$CERT_DIR/fullchain.pem" 2>/dev/null | cut -d= -f2)
        echo -e " ${GREEN}[ĐÃ CÓ]${NC} Chứng chỉ đã được cài đặt tại: ${YELLOW}$CERT_DIR${NC}"
        echo -e " ${CYAN}Hạn sử dụng đến:${NC} $expiry_date"
    else
        echo -e " ${YELLOW}(Chưa có chứng chỉ SSL nào được cài đặt trên hệ thống)${NC}"
    fi
}

# Xin chứng chỉ Cloudflare SSL
request_cloudflare_ssl() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} XIN CHỨNG CHỈ CLOUDFLARE SSL (ACME.SH)${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"

    read -p "Nhập tên miền của bạn (ví dụ: example.com hoặc sub.example.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}[LỖI] Tên miền không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Email tài khoản Cloudflare của bạn: " cf_email
    if [ -z "$cf_email" ]; then
        echo -e "${RED}[LỖI] Email Cloudflare không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Nhập Global API Key của Cloudflare: " cf_key
    if [ -z "$cf_key" ]; then
        echo -e "${RED}[LỖI] Global API Key không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    echo -e "${INFO} Đang kiểm tra và cài đặt công cụ acme.sh nếu chưa có..."
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}[LỖI] Không thể cài đặt acme.sh. Vui lòng kiểm tra lại kết nối mạng!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    # Đăng ký tài khoản acme.sh mặc định với Let's Encrypt nếu chưa có
    "$HOME/.acme.sh/acme.sh" --register-account -m "$cf_email" --server letsencrypt > /dev/null 2>&1

    export CF_Email="$cf_email"
    export CF_Key="$cf_key"

    echo -e "${INFO} Đang tiến hành yêu cầu cấp chứng chỉ qua Cloudflare DNS API cho miền: $domain và *.$domain..."
    
    # Xin chứng chỉ cho cả domain chính và wildcard (Chuyển CA sang Let's Encrypt)
    "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$domain" -d "*.$domain" --keylength ec-256 --server letsencrypt

    if [ $? -eq 0 ]; then
        echo -e "${SUCCESS} Xin chứng chỉ thành công! Đang tiến hành cài đặt chứng chỉ..."
        
        # Cài đặt chứng chỉ vào thư mục đích
        "$HOME/.acme.sh/acme.sh" --install-cert -d "$domain" --ecc \
            --fullchain-file "$CERT_DIR/fullchain.pem" \
            --key-file "$CERT_DIR/private.key"

        if [ $? -eq 0 ]; then
            log_success "Đã cài đặt chứng chỉ SSL thành công tại $CERT_DIR!"
            
            # Tự động gia hạn tự động qua cron job của acme.sh
            "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade > /dev/null 2>&1
        else
            echo -e "${RED}[LỖI] Đã xin được chứng chỉ nhưng gặp lỗi khi cài đặt vào đường dẫn đích.${NC}"
        fi
    else
        echo -e "${RED}[LỖI] Xin chứng chỉ thất bại. Vui lòng kiểm tra lại Domain, Email hoặc Global API Key!${NC}"
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Xem chi tiết chứng chỉ
view_ssl_details() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} CHI TIẾT CHỨNG CHỈ SSL${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"

    if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không tìm thấy chứng chỉ SSL nào trên hệ thống.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    openssl x509 -in "$CERT_DIR/fullchain.pem" -text -noout | head -n 30
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Nhấn Enter để tiếp tục..."
}

# Gỡ bỏ chứng chỉ SSL
remove_ssl() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${RED} GỠ BỎ CHỨNG CHỈ SSL${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"

    if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có chứng chỉ SSL nào để gỡ bỏ.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    read -p "Bạn có chắc chắn muốn xóa toàn bộ chứng chỉ SSL hiện tại không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$CERT_DIR/fullchain.pem" "$CERT_DIR/private.key"
        log_success "Đã xóa chứng chỉ SSL khỏi hệ thống thành công!"
    else
        echo "Đã hủy thao tác gỡ bỏ."
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Khởi chạy menu của module
render_ssl_menu