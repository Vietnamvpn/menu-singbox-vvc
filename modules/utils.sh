#!/bin/bash

# ==========================================
# modules/utils.sh - Các hàm tiện ích dùng chung
# ==========================================

# Định nghĩa màu sắc cho hiển thị CLI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/menu-singbox-vvc"

# Đường dẫn file log hệ thống
LOG_DIR="${INSTALL_DIR}/logs"
LOG_FILE="${LOG_DIR}/system.log"

# Đảm bảo thư mục log tồn tại
mkdir -p "$LOG_DIR"

# ==========================================
# CÁC HÀM GHI LOG
# ==========================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
    exit 1
}

# ==========================================
# CÁC HÀM HỆ THỐNG VÀ KIỂM TRA CORE
# ==========================================

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       log_error "Script này phải được chạy với quyền root (sudo)!"
    fi
}

# Kiểm tra trạng thái hoạt động của Sing-box core
get_singbox_status() {
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}Đang hoạt động (Running)${NC}"
    else
        echo -e "${RED}Đã dừng (Stopped)${NC}"
    fi
}

# Lấy phiên bản Sing-box core
get_singbox_version() {
    if command -v sing-box >/dev/null 2>&1; then
        local ver
        ver=$(sing-box version 2>/dev/null | grep -i "version" | awk '{print $3}')
        if [ -n "$ver" ]; then
            echo -e "${CYAN}$ver${NC}"
        else
            echo -e "${YELLOW}Không xác định${NC}"
        fi
    else
        echo -e "${RED}Chưa cài đặt${NC}"
    fi
}

# ==========================================
# CÁC HÀM ĐIỀU KHIỂN VÀ CẬP NHẬT SING-BOX CORE
# ==========================================

# Khởi động dịch vụ Sing-box
start_singbox() {
    log_info "Đang khởi động Sing-box..."
    systemctl start sing-box
    if systemctl is-active --quiet sing-box; then
        log_success "Sing-box đã khởi động thành công."
    else
        log_error "Không thể khởi động Sing-box. Vui lòng kiểm tra log!"
    fi
}

# Dừng dịch vụ Sing-box
stop_singbox() {
    log_info "Đang dừng Sing-box..."
    systemctl stop sing-box
    log_success "Đã dừng Sing-box."
}

# Khởi động lại dịch vụ Sing-box
restart_singbox() {
    log_info "Đang khởi động lại Sing-box..."
    systemctl restart sing-box
    if systemctl is-active --quiet sing-box; then
        log_success "Khởi động lại Sing-box thành công."
    else
        log_error "Không thể khởi động lại Sing-box. Vui lòng kiểm tra log!"
    fi
}

# Tự động cập nhật Sing-box Core mới nhất từ GitHub
update_singbox_core() {
    log_info "Đang kiểm tra và cập nhật Sing-box Core phiên bản mới nhất..."
    
    # Kiểm tra kiến trúc hệ thống
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Kiến trúc hệ thống $arch không được hỗ trợ tự động cập nhật core!" ;;
    esac

    log_info "Đang lấy thông tin bản phát hành mới nhất từ GitHub..."
    local latest_tag
    latest_tag=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$latest_tag" ]; then
        log_error "Không thể lấy thông tin phiên bản mới từ GitHub API!"
    fi

    log_info "Phiên bản mới nhất trên GitHub: $latest_tag"
    local version_clean=${latest_tag#v}
    
    local download_url="https://github.com/SagerNet/sing-box/releases/download/${latest_tag}/sing-box-${version_clean}-linux-${arch}.tar.gz"
    
    log_info "Đang tải xuống Sing-box Core..."
    cd /tmp
    if ! curl -L -o sing-box.tar.gz "$download_url"; then
        log_error "Tải xuống Sing-box Core thất bại!"
    fi

    log_info "Đang giải nén và cài đặt Core..."
    tar -xzf sing-box.tar.gz
    local extracted_dir="sing-box-${version_clean}-linux-${arch}"
    
    if [ -f "${extracted_dir}/sing-box" ]; then
        cp "${extracted_dir}/sing-box" /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -rf sing-box.tar.gz "${extracted_dir}"
        log_success "Cập nhật Sing-box Core thành công lên phiên bản $latest_tag!"
        restart_singbox
    else
        rm -rf sing-box.tar.gz "${extracted_dir}"
        log_error "Không tìm thấy tệp nhị phân sing-box sau khi giải nén!"
    fi
}

# ==========================================
# CÁC HÀM XỬ LÝ MẠNG VÀ PORT
# ==========================================

# Kiểm tra port đã được sử dụng chưa bằng netcat (nc)
check_port_in_use() {
    local port=$1
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
        return 0 # Port đang được sử dụng
    else
        return 1 # Port chưa được sử dụng (an toàn để dùng)
    fi
}

# Sinh port ngẫu nhiên chưa được sử dụng (từ 2000 đến 6000)
get_random_unused_port() {
    local port
    while true; do
        port=$(shuf -i 2000-6000 -n 1)
        if ! check_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
}

# ==========================================
# CÁC HÀM XỬ LÝ JSON BẰNG JQ
# ==========================================

# Đọc giá trị từ file JSON
# Cú pháp: read_json_value "file.json" ".key.path"
read_json_value() {
    local file=$1
    local path=$2
    if [[ -f "$file" ]]; then
        jq -r "$path" "$file" 2>/dev/null
    else
        echo ""
    fi
}

# Sửa hoặc thêm giá trị (chuỗi) vào file JSON
# Cú pháp: write_json_string "file.json" ".key.path" "giá trị"
write_json_string() {
    local file=$1
    local path=$2
    local value=$3
    local temp_file="${file}.tmp"
    
    if [[ -f "$file" ]]; then
        jq "$path = \"$value\"" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Sửa hoặc thêm giá trị (số/boolean) vào file JSON (không có ngoặc kép)
# Cú pháp: write_json_raw "file.json" ".key.path" "1234"
write_json_raw() {
    local file=$1
    local path=$2
    local value=$3
    local temp_file="${file}.tmp"
    
    if [[ -f "$file" ]]; then
        jq "$path = $value" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Trích xuất toàn bộ mảng hoặc object từ JSON để ghép nối
# Cú pháp: extract_json_block "file.json" ".key.path"
extract_json_block() {
    local file=$1
    local path=$2
    if [[ -f "$file" ]]; then
        jq -c "$path" "$file" 2>/dev/null
    else
        echo "[]"
    fi
}