#!/bin/bash

# ==========================================
# Script Cài Đặt Tự Động menu-singbox-vvc
# ==========================================

set -e

# Khai báo màu hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/menu-singbox-vvc"
REPO_URL="https://github.com/Vietnamvpn/menu-singbox-vvc.git"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 1. Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   log_error "Script này phải được chạy với quyền root (sudo)!"
fi

# 2. Kiểm tra Hệ Điều Hành và Cập nhật Hệ thống
log_info "Đang kiểm tra và cập nhật hệ thống..."
OS=""
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
fi

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget jq netcat-openbsd openssl ufw git tar golang-go
elif [[ "$OS" == "centos" || "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "rhel" ]]; then
    yum update -y
    yum install -y curl wget jq nc openssl firewalld git tar golang
else
    log_error "Hệ điều hành không được hỗ trợ chính thức: $OS"
fi

# Tự động kiểm tra và cài đặt grpcurl
if ! command -v grpcurl >/dev/null 2>&1; then
    log_info "Đang kiểm tra và cài đặt grpcurl..."
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) GRPCURL_ARCH="x86_64" ;;
        aarch64|arm64) GRPCURL_ARCH="arm64" ;;
        *) GRPCURL_ARCH="x86_64" ;;
    esac
    GRPCURL_VER="1.9.2"
    if wget -q "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VER}/grpcurl_${GRPCURL_VER}_linux_${GRPCURL_ARCH}.tar.gz" -O /tmp/grpcurl.tar.gz 2>/dev/null || \
       curl -sL "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VER}/grpcurl_${GRPCURL_VER}_linux_${GRPCURL_ARCH}.tar.gz" -o /tmp/grpcurl.tar.gz; then
        tar -zxf /tmp/grpcurl.tar.gz -C /usr/local/bin grpcurl 2>/dev/null || true
        chmod +x /usr/local/bin/grpcurl 2>/dev/null || true
        rm -f /tmp/grpcurl.tar.gz
    fi
    if command -v grpcurl >/dev/null 2>&1; then
        log_success "Cài đặt grpcurl thành công."
    else
        log_warn "Không thể cài đặt grpcurl tự động, hệ thống sẽ sử dụng apt/yum fallback khi chạy daemon."
    fi
fi

log_success "Cập nhật và cài đặt thư viện hệ thống hoàn tất."

# 3. Thiết lập Tường lửa (Firewall)
log_info "Đang cấu hình tường lửa..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw allow 8080/tcp >/dev/null 2>&1 || true
    echo "y" | ufw enable >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
    systemctl start firewalld || true
    systemctl enable firewalld || true
    firewall-cmd --permanent --add-port=22/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=80/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=443/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port=8080/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi
log_success "Đã mở cổng tường lửa cơ bản (22, 80, 443, 8080)."

# 4. Tải Mã Nguồn và Khởi Tạo Thư Mục
log_info "Đang chuẩn bị thư mục mã nguồn..."
mkdir -p "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "Cập nhật mã nguồn từ Git..."
    cd "$INSTALL_DIR" && git pull
else
    log_info "Tải mã nguồn từ GitHub..."
    git clone "$REPO_URL" "$INSTALL_DIR" || {
        log_warn "Không thể clone repository từ Git. Tạo cấu trúc thư mục cục bộ..."
        mkdir -p "$INSTALL_DIR"/{core,modules,data,certs,logs,templates/vless}
    }
fi

# Tạo đầy đủ cấu trúc thư mục chuẩn
mkdir -p "$INSTALL_DIR"/data
mkdir -p "$INSTALL_DIR"/certs/default
mkdir -p "$INSTALL_DIR"/logs
mkdir -p "$INSTALL_DIR"/core
mkdir -p "$INSTALL_DIR"/modules
mkdir -p "$INSTALL_DIR"/templates/vless

# 5. Khởi tạo Dữ liệu trạng thái ban đầu trong data/
log_info "Khởi tạo các tệp dữ liệu tĩnh..."
[ ! -s "$INSTALL_DIR/data/nodes.json" ] && echo "[]" > "$INSTALL_DIR/data/nodes.json"
[ ! -s "$INSTALL_DIR/data/users.json" ] && echo "[]" > "$INSTALL_DIR/data/users.json"
[ ! -s "$INSTALL_DIR/data/outbound.json" ] && echo "[]" > "$INSTALL_DIR/data/outbound.json"
[ ! -s "$INSTALL_DIR/data/routing.json" ] && echo "[]" > "$INSTALL_DIR/data/routing.json"
[ ! -s "$INSTALL_DIR/data/domain.json" ] && echo "[]" > "$INSTALL_DIR/data/domain.json"
[ ! -s "$INSTALL_DIR/data/entry-node.json" ] && echo "[]" > "$INSTALL_DIR/data/entry-node.json"

# 6. Khởi tạo Chứng chỉ SSL tạm thời (Self-Signed) khi chưa xin từ Cloudflare
if [ ! -f "$INSTALL_DIR/certs/default/cert.pem" ]; then
    log_info "Đang khởi tạo chứng chỉ SSL mặc định (Self-Signed)..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$INSTALL_DIR/certs/default/private.key" \
        -out "$INSTALL_DIR/certs/default/cert.pem" \
        -subj "/CN=singbox-default-node" >/dev/null 2>&1
    log_success "Tạo chứng chỉ SSL mặc định thành công."
fi

# 7. Tải và Cài đặt Sing-box Core phiên bản mới nhất từ Vietnamvpn/sing-box
log_info "Đang kiểm tra phiên bản Sing-box Core mới nhất từ Vietnamvpn/sing-box..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) SINGBOX_ARCH="amd64" ;;
    aarch64|arm64) SINGBOX_ARCH="arm64" ;;
    *) log_error "Kiến trúc CPU không được hỗ trợ: $ARCH" ;;
esac

VERSION=$(curl -s "https://api.github.com/repos/Vietnamvpn/sing-box/releases/latest" | jq -r '.tag_name // empty')
if [ -z "$VERSION" ]; then
    log_warn "Không thể lấy phiên bản mới nhất từ GitHub API, chuyển sang dùng phiên bản dự phòng v1.13.14"
    VERSION="v1.13.14"
fi

DOWNLOAD_URL="https://github.com/Vietnamvpn/sing-box/releases/download/${VERSION}/sing-box-linux-${SINGBOX_ARCH}"

log_info "Đang tải xuống Sing-box ${VERSION} (${SINGBOX_ARCH})..."
if ! wget -q "$DOWNLOAD_URL" -O /usr/local/bin/sing-box; then
    curl -L -o /usr/local/bin/sing-box "$DOWNLOAD_URL" || log_error "Tải xuống Sing-box Core thất bại!"
fi
chmod +x /usr/local/bin/sing-box
log_success "Cài đặt Sing-box Core ${VERSION} thành công."

# 8. Biên dịch Go Daemon (api_server.go)
if [ -f "$INSTALL_DIR/core/api_server.go" ]; then
    log_info "Đang biên dịch Go Daemon (api_server.go)..."
    cd "$INSTALL_DIR/core"
    go build -o "$INSTALL_DIR/core/api_server" api_server.go
    chmod +x "$INSTALL_DIR/core/api_server"
    log_success "Biên dịch Go Daemon thành công."
fi

# 9. Đăng ký Systemd Services
log_info "Đang đăng ký Dịch vụ Systemd..."
mkdir -p /etc/sing-box

if [ -f "$INSTALL_DIR/templates/sing-box.service" ]; then
    cp "$INSTALL_DIR/templates/sing-box.service" /etc/systemd/system/sing-box.service
fi

if [ -f "$INSTALL_DIR/templates/manager.service" ]; then
    cp "$INSTALL_DIR/templates/manager.service" /etc/systemd/system/manager.service
fi

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1 || true
systemctl enable manager >/dev/null 2>&1 || true

# 10. Tạo lệnh gõ 'vvc' vào Menu quản lý
chmod +x "$INSTALL_DIR/main.sh"
ln -sf "$INSTALL_DIR/main.sh" /usr/local/bin/vvc
chmod +x /usr/local/bin/vvc

log_success "=================================================="
log_success "${GREEN} LẮP ĐẶT HOÀN TẤT HỆ THỐNG MENU SINGBOX VVC${NC}"
echo -e "${YELLOW} Gõ lệnh: vvc để truy cập Menu Quản Lý${NC}"
echo -e "======================================================="