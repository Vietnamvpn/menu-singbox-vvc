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

# Hàm kiểm tra dung lượng và làm mới log nếu >= 1MB (1048576 bytes)
append_log() {
    local level="$1"
    local msg="$2"
    
    if [ -f "$LOG_FILE" ]; then
        local file_size
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$file_size" -ge 1048576 ]; then
            > "$LOG_FILE" # Làm trống file log
        fi
    fi
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    append_log "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    append_log "SUCCESS" "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    append_log "WARN" "$1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    append_log "ERROR" "$1"
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
        echo -e "${GREEN}Đang Chạy${NC}"
    else
        echo -e "${RED}Đang dừng${NC}"
    fi
}

# Lấy chính xác phiên bản Sing-box core từ dòng đầu tiên
get_singbox_version() {
    local bin_path="/usr/local/bin/sing-box"
    if [ -f "$bin_path" ] && [ -x "$bin_path" ]; then
        local ver
        # Lấy từ khóa ở cột thứ 3 của dòng đầu tiên (ví dụ: "sing-box version 1.13.14" -> "1.13.14" hoặc "unknown")
        ver=$($bin_path version 2>/dev/null | head -n 1 | awk '{print $3}')
        
        if [ -n "$ver" ] && [ "$ver" != "unknown" ]; then
            echo -e "${CYAN}$ver${NC}"
        elif [ "$ver" == "unknown" ]; then
            echo -e "unknown"
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
    latest_tag=$(curl -s https://api.github.com/repos/Vietnamvpn/sing-box/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$latest_tag" ]; then
        log_error "Không thể lấy thông tin phiên bản mới từ GitHub API!"
    fi

    log_info "Phiên bản mới nhất trên GitHub: $latest_tag"
    
    local download_url="https://github.com/Vietnamvpn/sing-box/releases/download/${latest_tag}/sing-box-linux-${arch}"
    
    log_info "Đang tải xuống Sing-box Core..."
    cd /tmp
    if ! curl -L -o sing-box "$download_url"; then
        log_error "Tải xuống Sing-box Core thất bại!"
    fi

    log_info "Đang cài đặt Core..."
    if [ -f "sing-box" ]; then
        cp sing-box /usr/local/bin/sing-box
        chmod +x /usr/local/bin/sing-box
        rm -f sing-box
        log_success "Cập nhật Sing-box Core thành công lên phiên bản $latest_tag!"
        restart_singbox
    else
        rm -f sing-box
        log_error "Không tìm thấy tệp nhị phân sing-box sau khi tải xuống!"
    fi
}

# ==========================================
# CÁC HÀM TÍNH NĂNG MỚI: XÓA HỆ THỐNG, BẬT BBR, THÊM SWAP
# ==========================================

# Xóa toàn bộ mã nguồn, dịch vụ và cấu hình liên quan
uninstall_system() {
    check_root
    log_warn "Cảnh báo: Thao tác này sẽ xóa toàn bộ mã nguồn, dịch vụ và cấu hình hệ thống!"
    read -p "Bạn có chắc chắn muốn gỡ bỏ hoàn toàn hệ thống không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Đang dừng các dịch vụ hệ thống..."
        systemctl stop sing-box manager >/dev/null 2>&1 || true
        systemctl disable sing-box manager >/dev/null 2>&1 || true
        
        log_info "Đang xóa các tệp dịch vụ Systemd..."
        rm -f /etc/systemd/system/sing-box.service
        rm -f /etc/systemd/system/manager.service
        systemctl daemon-reload
        
        log_info "Đang xóa các tệp nhị phân và lệnh tắt..."
        rm -f /usr/local/bin/sing-box
        rm -f /usr/local/bin/vvc
        rm -rf /etc/sing-box
        
        log_info "Đang xóa thư mục mã nguồn $INSTALL_DIR..."
        if [ -d "$INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
            log_success "Đã gỡ bỏ hoàn toàn hệ thống và dọn dẹp dữ liệu thành công."
            exit 0
        else
            log_warn "Thư mục cài đặt không tồn tại hoặc đã được xóa trước đó."
            exit 0
        fi
    else
        log_info "Đã hủy thao tác gỡ bỏ hệ thống."
    fi
}

# Bật thuật toán kiểm soát tắc nghẽn TCP BBR
enable_bbr() {
    check_root
    log_info "Đang kiểm tra và cấu hình TCP BBR..."
    
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" == "bbr" ]; then
        log_success "TCP BBR đã được kích hoạt từ trước."
        return 0
    fi

    local sysctl_conf="/etc/sysctl.conf"
    if [ ! -f "$sysctl_conf" ]; then
        log_error "Không tìm thấy tệp cấu hình $sysctl_conf!"
    fi

    # Xóa các dòng cấu hình cũ nếu có để tránh trùng lặp
    sed -i '/net.core.default_qdisc/d' "$sysctl_conf"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$sysctl_conf"

    echo "net.core.default_qdisc=fq" >> "$sysctl_conf"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$sysctl_conf"

    if sysctl -p >/dev/null 2>&1; then
        local check_bbr
        check_bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [ "$check_bbr" == "bbr" ]; then
            log_success "Kích hoạt TCP BBR thành công!"
        else
            log_error "Kích hoạt TCP BBR thất bại, hệ thống không chấp nhận cấu hình."
        fi
    else
        log_error "Không thể áp dụng cấu hình sysctl bằng lệnh sysctl -p!"
    fi
}

# Thêm bộ nhớ Swap cho hệ thống
add_swap() {
    check_root
    local swap_size="${1:-2G}" # Mặc định 2G nếu không truyền tham số
    log_info "Đang kiểm tra và thiết lập Swap (dung lượng: $swap_size)..."

    if [ "$(free -m | grep Swap | awk '{print $2}')" -gt 0 ]; then
        log_warn "Hệ thống đã có phân vùng/tệp Swap đang hoạt động."
        free -h
        read -p "Bạn có muốn tạo thêm hoặc thay thế Swap không? (y/N): " swap_confirm
        if [[ ! "$swap_confirm" =~ ^[Yy]$ ]]; then
            log_info "Đã hủy thao tác thêm Swap."
            return 0
        fi
    fi

    local swap_file="/swapfile"
    if [ -f "$swap_file" ]; then
        log_warn "Tệp $swap_file đã tồn tại. Đang tiến hành tắt và xóa tệp swap cũ..."
        swapoff "$swap_file" >/dev/null 2>&1 || true
        rm -f "$swap_file"
    fi

    log_info "Đang tạo tệp swap dung lượng $swap_size..."
    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "$swap_size" "$swap_file" || dd if=/dev/zero of="$swap_file" bs=1M count=2048 status=progress
    else
        dd if=/dev/zero of="$swap_file" bs=1M count=2048 status=progress
    fi

    if [ ! -f "$swap_file" ]; then
        log_error "Không thể tạo tệp swap!"
    fi

    log_info "Đang thiết lập quyền bảo mật cho tệp swap..."
    chmod 600 "$swap_file"

    log_info "Đang định dạng tệp swap..."
    if ! mkswap "$swap_file" >/dev/null 2>&1; then
        rm -f "$swap_file"
        log_error "Lỗi khi định dạng mkswap cho tệp swap!"
    fi

    log_info "Đang kích hoạt Swap..."
    if ! swapon "$swap_file" >/dev/null 2>&1; then
        rm -f "$swap_file"
        log_error "Không thể kích hoạt tệp swap bằng swapon!"
    fi

    # Thêm cấu hình vào /etc/fstab để tự động bật khi khởi động lại (tránh trùng lặp)
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "$swap_file none swap sw 0 0" >> /etc/fstab
        log_success "Đã cấu hình tự động bật Swap khi khởi động lại hệ thống."
    fi

    log_success "Thiết lập Swap thành công dung lượng $swap_size!"
    free -h
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

# Lấy tên quốc gia theo IP của VPS hiện tại (Hỗ trợ dự phòng qua ipapi.co và ipinfo.io)
get_vps_country() {
    local country=""
    country=$(curl -s --max-time 4 https://ipapi.co/country_name 2>/dev/null)
    if [ -z "$country" ] || [ "$country" = "Undefined" ] || [[ "$country" == *"error"* ]]; then
        country=$(curl -s --max-time 4 https://ipinfo.io/country 2>/dev/null)
    fi
    if [ -z "$country" ]; then
        country="Unknown"
    fi
    echo "$country"
}

# ==========================================
# CÁC HÀM XỬ LÝ JSON BẰNG JQ
# ==========================================

# Đọc giá trị từ file JSON
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
write_json_string() {
    local file=$1
    local path=$2
    local value=$3
    local temp_file="${file}.tmp"
    
    if [[ -f "$file" ]]; then
        jq "$path = \"$value\"" "$file" > "$temp_file" && mv "$temp_file" "$file"
    fi
}

# Sửa hoặc thêm giá trị (số/boolean) vào file JSON
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
extract_json_block() {
    local file=$1
    local path=$2
    if [[ -f "$file" ]]; then
        jq -c "$path" "$file" 2>/dev/null
    else
        echo "[]"
    fi
}

# ==========================================
# HÀM BIÊN DỊCH VÀ ÁP DỤNG CẤU HÌNH (BUILD)
# ==========================================

build_and_apply_config() {
    local base_file="${1:-${INSTALL_DIR}/templates/config.base.json}"
    local output_file="${2:-/etc/sing-box/config.json}"
    local data_dir="${DATA_DIR:-${INSTALL_DIR}/data}"
    
    log_info "Bắt đầu tạo file cấu hình cho Sing-box: $output_file"
    
    if [ ! -f "$base_file" ]; then
        log_error "File base config không tồn tại: $base_file"
        return 1
    fi
    
    if [ ! -f "$data_dir/nodes.json" ] || [ ! -f "$data_dir/users.json" ]; then
        log_error "Thiếu file dữ liệu nodes.json hoặc users.json"
        return 1
    fi

    local temp_output="/tmp/singbox_config_temp.json"
    local routing_file="$data_dir/routing.json"
    
    jq --argjson nodes "$(cat "$data_dir/nodes.json")" \
       --argjson users "$(cat "$data_dir/users.json")" \
       --argjson routings "$([ -f "$routing_file" ] && cat "$routing_file" || echo "[]")" \
       '
       .inbounds = [] |
       .inbounds = (
         $nodes | map(
           . as $n |
           ($users | map(select((.status == "active" or .status == null or .status == "") and (.tag == $n.tag or .tag == "all")))) as $matched_users |
           
           if $n.type == "vless-grpc-reality" then
             {
               type: "vless",
               tag: $n.tag,
               listen: "::",
               listen_port: ($n.port | tonumber),
               users: ($matched_users | map({name: (.username // .Username), uuid: (.uuid // .UUID)})),
               tls: {
                 enabled: true,
                 server_name: $n.sni,
                 reality: {
                   enabled: true,
                   handshake: {
                     server: $n.sni,
                     server_port: 443
                   },
                   private_key: $n.public_key,
                   short_id: [$n.short_id]
                 }
               },
               transport: {
                 type: "grpc",
                 service_name: $n.grpc_service
               }
             }
           elif $n.type == "vless-ws-tls" then
             {
               type: "vless",
               tag: $n.tag,
               listen: "::",
               listen_port: ($n.port | tonumber),
               users: ($matched_users | map({name: (.username // .Username), uuid: (.uuid // .UUID)})),
               tls: {
                 enabled: true,
                 server_name: ($n.domain // $n.sni // "160.250.180.35"),
                 certificate_path: ($n.cert_path // "/opt/menu-singbox-vvc/certs/default/cert.pem"),
                 key_path: ($n.key_path // "/opt/menu-singbox-vvc/certs/default/private.key")
               },
               transport: {
                 type: "ws",
                 path: $n.ws_path
               }
             }
           elif $n.type == "hysteria2" then
             {
               type: "hysteria2",
               tag: $n.tag,
               listen: "::",
               listen_port: ($n.port | tonumber),
               users: ($matched_users | map({name: (.username // .Username), password: (.uuid // .UUID)})),
               up_mbps: 100,
               down_mbps: 100,
               tls: {
                 enabled: true,
                 certificate_path: ($n.cert_path // "/opt/menu-singbox-vvc/certs/default/cert.pem"),
                 key_path: ($n.key_path // "/opt/menu-singbox-vvc/certs/default/private.key")
               }
             }
           elif $n.type == "tuic" then
             {
               type: "tuic",
               tag: $n.tag,
               listen: "::",
               listen_port: ($n.port | tonumber),
               users: ($matched_users | map({name: (.username // .Username), uuid: (.uuid // .UUID), password: ($n.password // "0TnownUlPQZdJWrc")})),
               tls: {
                 enabled: true,
                 server_name: ($n.domain // $n.sni // "160.250.180.35"),
                 alpn: ["h3"],
                 certificate_path: ($n.cert_path // "/opt/menu-singbox-vvc/certs/default/cert.pem"),
                 key_path: ($n.key_path // "/opt/menu-singbox-vvc/certs/default/private.key")
               }
             }
           elif $n.type == "vless-reality" then
             {
               type: "vless",
               tag: $n.tag,
               listen: "::",
               listen_port: ($n.port | tonumber),
               users: ($matched_users | map({name: (.username // .Username), uuid: (.uuid // .UUID), flow: "xtls-rprx-vision"})),
               tls: {
                 enabled: true,
                 server_name: $n.sni,
                 reality: {
                   enabled: true,
                   handshake: {
                     server: $n.sni,
                     server_port: 443
                   },
                   private_key: $n.public_key,
                   short_id: [$n.short_id]
                 }
               }
             }
           else
             empty
           end
         )
       ) |
       if ($routings | length) > 0 then
         .route.rules = ((.route.rules // []) + $routings)
       else
         .
       end
       ' "$base_file" > "$temp_output"

    if [ $? -ne 0 ]; then
        log_error "Lỗi cú pháp khi tạo file cấu hình JSON bằng jq"
        rm -f "$temp_output"
        return 1
    fi

    local check_output
    if ! check_output=$(sing-box check -c "$temp_output" 2>&1); then
        echo -e "\033[0;31m[CHI TIẾT LỖI SING-BOX CHECK]:\033[0m"
        echo "$check_output"
        log_error "Cấu hình Sing-box tạo ra không hợp lệ"
        rm -f "$temp_output"
        return 1
    fi

    mv "$temp_output" "$output_file"
    log_info "Đã cập nhật file cấu hình Sing-box thành công tại: $output_file"
    
    if systemctl is-active --quiet sing-box; then
        log_info "Đang reload dịch vụ Sing-box..."
        systemctl reload sing-box || systemctl restart sing-box
    else
        log_info "Đang khởi động dịch vụ Sing-box..."
        systemctl start sing-box
    fi
}

# ==========================================
# HÀM RÁP LINK CHIA SẺ CHO APP (VLESS REALITY)
# ==========================================

generate_vless_reality_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local sni="$5"
    local public_key="$6"
    local short_id="$7"
    
    local link="vless://${uuid}@${address}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#${tag}"
    
    echo "$link"
}

generate_vless_grpc_reality_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local sni="$5"
    local public_key="$6"
    local short_id="$7"
    local service_name="$8"
    
    local link="vless://${uuid}@${address}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=grpc&serviceName=${service_name}#${tag}"
    
    echo "$link"
}

# Ráp link cho VLESS WS TLS (Thêm &allowInsecure=1)
generate_vless_ws_tls_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local domain="$5"
    local ws_path="$6"
    
    local link="vless://${uuid}@${address}:${port}?encryption=none&security=tls&sni=${domain}&type=ws&path=${ws_path}&allowInsecure=1#${tag}"
    
    echo "$link"
}

# Ráp link cho Hysteria2 (Thêm &insecure=1)
generate_hysteria2_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local password="$4"
    local domain="$5"
    
    local link="hysteria2://${password}@${address}:${port}?sni=${domain}&insecure=1#${tag}"
    
    echo "$link"
}

# Ráp link cho TUIC (Thêm &insecure=1)
generate_tuic_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local password="$5"
    local domain="$6"
    
    local link="tuic://${uuid}:${password}@${address}:${port}?congestion_control=bbr&sni=${domain}&alpn=h3&insecure=1#${tag}"
    
    echo "$link"
}