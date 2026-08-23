#!/bin/bash

API_CONFIG_FILE="/opt/menu-singbox-vvc/data/api_config.json"

# Đảm bảo thư mục dữ liệu tồn tại
mkdir -p "$(dirname "$API_CONFIG_FILE")"

# Hiển thị menu quản lý API Web trung tâm
render_api_menu() {
    while true; do
        clear
        echo "================================================================"
        echo "||                  QUẢN LÝ API WEB TRUNG TÂM                 ||"
        echo "================================================================"
        
        # Đọc cấu hình hiện tại
        local current_url="Chưa cấu hình"
        local current_token="Chưa cấu hình"
        if [ -f "$API_CONFIG_FILE" ]; then
            local url_val
            url_val=$(jq -r '.url // empty' "$API_CONFIG_FILE" 2>/dev/null)
            local token_val
            token_val=$(jq -r '.token // empty' "$API_CONFIG_FILE" 2>/dev/null)
            [ -n "$url_val" ] && current_url="$url_val"
            if [ -n "$token_val" ]; then
                if [ ${#token_val} -gt 6 ]; then
                    current_token="${token_val:0:6}..."
                else
                    current_token="******"
                fi
            fi
        fi

        # Kiểm tra trạng thái dịch vụ manager.service
        local service_status="Đang dừng"
        if systemctl is-active --quiet manager; then
            service_status="Đang chạy"
        fi

        echo " - URL Web Hiện Tại : $current_url"
        echo " - Token Xác Thực   : $current_token"
        echo " - Trạng Thái Daemon: $service_status"
        echo "================================================================"
        echo " 1. Thêm / Cập nhật URL & Token API"
        echo " 2. Bật dịch vụ API Daemon (Manager)"
        echo " 3. Tắt dịch vụ API Daemon (Manager)"
        echo " 4. Kiểm tra kết nối tới Web Trung Tâm"
        echo " 0. Quay lại Menu Chính"
        echo "================================================================"
        read -p " Vui lòng chọn một chức năng [0-4]: " choice

        case "$choice" in
            1)
                configure_api_credentials
                ;;
            2)
                systemctl start manager
                systemctl enable manager >/dev/null 2>&1
                log_success "Đã khởi động dịch vụ API Daemon thành công."
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                systemctl stop manager
                systemctl disable manager >/dev/null 2>&1
                log_warn "Đã dừng dịch vụ API Daemon."
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            4)
                test_api_connection
                ;;
            0)
                break
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ, vui lòng chọn từ 0 đến 4."
                sleep 1
                ;;
        esac
    done
}

# Cấu hình nhập URL và Token
configure_api_credentials() {
    echo "--------------------------------------------------"
    echo " NHẬP THÔNG TIN KẾT NỐI WEB TRUNG TÂM"
    echo "--------------------------------------------------"
    
    local old_url=""
    local old_token=""
    if [ -f "$API_CONFIG_FILE" ]; then
        old_url=$(jq -r '.url // ""' "$API_CONFIG_FILE" 2>/dev/null)
        old_token=$(jq -r '.token // ""' "$API_CONFIG_FILE" 2>/dev/null)
    fi

    read -p "Nhập URL Web Trung Tâm [Mặc định: $old_url]: " input_url
    input_url="${input_url:-$old_url}"

    read -p "Nhập Token Xác Thực [Giữ nguyên nếu bỏ trống]: " input_token
    input_token="${input_token:-$old_token}"

    if [ -z "$input_url" ]; then
        log_warn "URL không được để trống!"
        sleep 2
        return
    fi

    # Ghi tệp JSON an toàn bằng jq
    jq -n --arg u "$input_url" --arg t "$input_token" '{url: $u, token: $t}' > "$API_CONFIG_FILE"

    log_success "Đã lưu cấu hình API thành công!"
    
    # Khởi động lại service manager để nhận config mới nếu đang chạy
    if systemctl is-active --quiet manager; then
        systemctl restart manager
        log_info "Đã khởi động lại dịch vụ Manager để áp dụng thay đổi."
    fi
    
    read -p "Nhấn Enter để tiếp tục..."
}

# Kiểm tra kết nối nhanh tới web trung tâm
test_api_connection() {
    echo "--------------------------------------------------"
    echo " KIỂM TRA KẾT NỐI WEB TRUNG TÂM"
    echo "--------------------------------------------------"
    if [ ! -f "$API_CONFIG_FILE" ]; then
        log_warn "Chưa có cấu hình API nào được lưu."
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local url
    url=$(jq -r '.url // ""' "$API_CONFIG_FILE" 2>/dev/null)
    local token
    token=$(jq -r '.token // ""' "$API_CONFIG_FILE" 2>/dev/null)

    if [ -z "$url" ]; then
        log_warn "URL trống, không thể kiểm tra."
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    log_info "Đang gửi tín hiệu kiểm tra tới: $url ..."
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" "$url/sync-commands")
    
    if [ "$response" = "200" ] || [ "$response" = "401" ]; then
        log_success "Kết nối thành công tới Web Trung Tâm! (Mã phản hồi HTTP: $response)"
    else
        log_warn "Không thể kết nối ổn định (Mã phản hồi HTTP: $response). Vui lòng kiểm tra lại URL hoặc Token."
    fi
    read -p "Nhấn Enter để tiếp tục..."
}