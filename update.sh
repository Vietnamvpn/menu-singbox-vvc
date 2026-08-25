#!/bin/bash

# ==========================================
# Script Cập Nhật Tự Động menu-singbox-vvc
# ==========================================

set -e

# Khai báo màu hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/menu-singbox-vvc"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 1. Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   log_error "Script này phải được chạy với quyền root (sudo)!"
fi

log_info "Đang bắt đầu quá trình cập nhật và khôi phục hệ thống..."

# 2. Cập nhật mã nguồn từ Git (Có cơ chế bảo vệ thư mục data/ không bị xóa)
if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "Đang sao lưu tạm thời dữ liệu người dùng (data/)..."
    if [ -d "$INSTALL_DIR/data" ]; then
        rm -rf /tmp/vvc_data_backup
        cp -r "$INSTALL_DIR/data" /tmp/vvc_data_backup
    fi

    log_info "Đang kéo mã nguồn mới nhất từ GitHub..."
    cd "$INSTALL_DIR"
    git fetch --all
    git reset --hard origin/main || git reset --hard origin/master || true
    git pull || true

    log_info "Đang khôi phục lại dữ liệu người dùng..."
    if [ -d "/tmp/vvc_data_backup" ]; then
        mkdir -p "$INSTALL_DIR/data"
        cp -rf /tmp/vvc_data_backup/* "$INSTALL_DIR/data/"
        rm -rf /tmp/vvc_data_backup
    fi
else
    log_warn "Không phát hiện thư mục Git, bỏ qua bước git pull."
fi

# 3. Kiểm tra và tự động khôi phục cấu trúc thư mục bị thiếu
log_info "Đang kiểm tra cấu trúc thư mục..."
DIRS=(
    "$INSTALL_DIR/core"
    "$INSTALL_DIR/modules"
    "$INSTALL_DIR/data"
    "$INSTALL_DIR/certs/default"
    "$INSTALL_DIR/logs"
    "$INSTALL_DIR/templates/vless"
)

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        log_warn "Thư mục bị thiếu: $dir -> Đang tự động tạo mới..."
        mkdir -p "$dir"
    fi
done

# 4. Kiểm tra và tự động khôi phục các tệp JSON dữ liệu bị thiếu hoặc rỗng
log_info "Đang kiểm tra các tệp dữ liệu trong data/..."
declare -A DATA_FILES=(
    ["$INSTALL_DIR/data/nodes.json"]="[]"
    ["$INSTALL_DIR/data/users.json"]="[]"
    ["$INSTALL_DIR/data/outbound.json"]="[]"
    ["$INSTALL_DIR/data/routing.json"]="[]"
    ["$INSTALL_DIR/data/domain.json"]="[]"
    ["$INSTALL_DIR/data/entry-node.json"]="[]"
)

for file in "${!DATA_FILES[@]}"; do
    if [ ! -s "$file" ]; then
        log_warn "Tệp dữ liệu bị thiếu hoặc rỗng: $file -> Đang khởi tạo lại..."
        echo "${DATA_FILES[$file]}" > "$file"
    fi
done

# 5. Kiểm tra và tự động tạo lại chứng chỉ SSL mặc định nếu bị mất
if [ ! -f "$INSTALL_DIR/certs/default/cert.pem" ] || [ ! -f "$INSTALL_DIR/certs/default/private.key" ]; then
    log_warn "Chứng chỉ SSL mặc định bị thiếu -> Đang tự động sinh lại..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$INSTALL_DIR/certs/default/private.key" \
        -out "$INSTALL_DIR/certs/default/cert.pem" \
        -subj "/CN=singbox-default-node" >/dev/null 2>&1
    log_success "Đã tạo lại chứng chỉ SSL mặc định."
fi

# 6. Biên dịch lại Go Daemon (api_server.go)
if [ -f "$INSTALL_DIR/core/api_server.go" ]; then
    log_info "Đang biên dịch lại Go Daemon (api_server.go)..."
    cd "$INSTALL_DIR/core"
    if command -v go >/dev/null 2>&1; then
        go build -o "$INSTALL_DIR/core/api_server" api_server.go
        chmod +x "$INSTALL_DIR/core/api_server"
        log_success "Biên dịch Go Daemon thành công."
    else
        log_warn "Không tìm thấy golang để biên dịch api_server.go!"
    fi
fi

# 7. Cập nhật và đăng ký lại Systemd Services
log_info "Đang cập nhật cấu hình dịch vụ Systemd..."
if [ -f "$INSTALL_DIR/templates/sing-box.service" ]; then
    cp "$INSTALL_DIR/templates/sing-box.service" /etc/systemd/system/sing-box.service
fi

if [ -f "$INSTALL_DIR/templates/manager.service" ]; then
    cp "$INSTALL_DIR/templates/manager.service" /etc/systemd/system/manager.service
fi

systemctl daemon-reload
systemctl restart manager >/dev/null 2>&1 || true

# 8. Cấp quyền thực thi cho toàn bộ script và liên kết lại lệnh vvc
log_info "Cập nhật quyền thực thi và menu điều khiển..."
chmod +x "$INSTALL_DIR/main.sh"
chmod +x "$INSTALL_DIR/install.sh"
chmod +x "$INSTALL_DIR/update.sh"
if [ -d "$INSTALL_DIR/modules" ]; then
    chmod +x "$INSTALL_DIR/modules"/*.sh 2>/dev/null || true
fi

ln -sf "$INSTALL_DIR/main.sh" /usr/local/bin/vvc
chmod +x /usr/local/bin/vvc

log_success "=================================================="
log_success " CẬP NHẬT HOÀN TẤT!"
log_success " Tất cả tệp bị thiếu đã được khôi phục."
log_success " Dữ liệu node và user của bạn được bảo vệ an toàn."
echo -e "${YELLOW} Hệ thống đang tự động thoát menu. Hãy gõ lệnh (vvc) để vào lại và áp dụng các thay đổi.${NC}"
echo -e "======================================================="

# Chờ 2 giây để người dùng kịp đọc thông báo, sau đó tự động tắt tiến trình gọi (main menu)
sleep 2
kill -9 $PPID 2>/dev/null