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
    log_info "Đang tiến hành biên dịch cấu hình Sing-box..."
    
    local base_config="${INSTALL_DIR}/templates/config.base.json"
    local dest_config="/etc/sing-box/config.json"
    local nodes_file="${INSTALL_DIR}/data/nodes.json"
    local users_file="${INSTALL_DIR}/data/users.json"
    local outbound_file="${INSTALL_DIR}/data/outbound.json"
    
    # 1. Kiểm tra file mẫu và file dữ liệu
    if [ ! -f "$base_config" ]; then
        log_error "File mẫu $base_config không tồn tại!"
    fi

    if [ ! -f "$nodes_file" ]; then
        echo "[]" > "$nodes_file"
    fi

    if [ ! -f "$users_file" ]; then
        echo "[]" > "$users_file"
    fi

    if [ ! -f "$outbound_file" ]; then
        echo "[]" > "$outbound_file"
    fi

    # 2. Kiểm tra thư mục đích
    if [ ! -d "/etc/sing-box" ]; then
        mkdir -p "/etc/sing-box"
    fi

    log_info "Đang tổng hợp nodes, users và outbounds vào cấu hình..."
    
    # 3. Sử dụng jq để kết hợp base_config, nodes, users và outbounds
    if jq --slurpfile nodes "$nodes_file" --slurpfile users "$users_file" --slurpfile outbounds "$outbound_file" '
        .inbounds = [
            ($nodes[0][]? | . as $n | 
                ([$users[0][]? | select(.tag == $n.tag or .tag == "all")]) as $matched_users |
                
                if $n.type == "vless-reality" then
                    {
                        type: "vless",
                        tag: $n.tag,
                        listen: "::",
                        listen_port: $n.port,
                        users: ([$matched_users[] | {uuid: .secret, flow: "xtls-rprx-vision"}]),
                        tls: {
                            enabled: true,
                            server_name: $n.sni,
                            reality: {
                                enabled: true,
                                handshake: {
                                    server: $n.sni,
                                    server_port: 443
                                },
                                private_key: $n.private_key,
                                short_id: [$n.short_id]
                            }
                        }
                    }
                elif $n.type == "vless-ws-tls" then
                    {
                        type: "vless",
                        tag: $n.tag,
                        listen: "::",
                        listen_port: $n.port,
                        users: ([$matched_users[] | {uuid: .secret}]),
                        tls: {
                            enabled: true,
                            server_name: $n.domain,
                            certificate_path: $n.cert_path,
                            key_path: $n.key_path
                        },
                        transport: {
                            type: "ws",
                            path: $n.ws_path
                        }
                    }
                elif $n.type == "vless-grpc-reality" then
                    {
                        type: "vless",
                        tag: $n.tag,
                        listen: "::",
                        listen_port: $n.port,
                        users: ([$matched_users[] | {uuid: .secret}]),
                        tls: {
                            enabled: true,
                            server_name: $n.sni,
                            reality: {
                                enabled: true,
                                handshake: {
                                    server: $n.sni,
                                    server_port: 443
                                },
                                private_key: $n.private_key,
                                short_id: [$n.short_id]
                            }
                        },
                        transport: {
                            type: "grpc",
                            service_name: $n.grpc_service
                        }
                    }
                elif $n.type == "hysteria2" then
                    {
                        type: "hysteria2",
                        tag: $n.tag,
                        listen: "::",
                        listen_port: $n.port,
                        users: (if ($matched_users | length) > 0 then [$matched_users[] | {password: .secret}] else [{password: $n.password}] end),
                        up_mbps: ($n.up_mbps | tonumber),
                        down_mbps: ($n.down_mbps | tonumber),
                        tls: {
                            enabled: true,
                            certificate_path: $n.cert_path,
                            key_path: $n.key_path
                        }
                    }
                elif $n.type == "tuic" then
                    {
                        type: "tuic",
                        tag: $n.tag,
                        listen: "::",
                        listen_port: $n.port,
                        users: (if ($matched_users | length) > 0 then [$matched_users[] | {uuid: .secret, password: $n.password}] else [{uuid: $n.uuid, password: $n.password}] end),
                        tls: {
                            enabled: true,
                            server_name: $n.domain,
                            alpn: ["h3"],
                            certificate_path: $n.cert_path,
                            key_path: $n.key_path
                        }
                    }
                else
                    empty
                end
            )
        ] |
        .outbounds = (.outbounds + $outbounds[0])
    ' "$base_config" > "${dest_config}.tmp"; then
        
        mv "${dest_config}.tmp" "$dest_config"
        log_success "Biên dịch cấu hình thành công tại $dest_config"
        
        # 4. Kiểm tra tính hợp lệ và khởi động lại dịch vụ
        log_info "Đang kiểm tra tính hợp lệ của cấu hình vừa tạo..."
        
        local check_output
        check_output=$(sing-box check -c "$dest_config" 2>&1)
        
        if [ $? -eq 0 ]; then
            log_success "Cấu hình hợp lệ!"
            restart_singbox
        else
            log_error "Cấu hình không hợp lệ! Chi tiết từ Sing-box:\n$check_output"
        fi
    else
        rm -f "${dest_config}.tmp"
        log_error "Biên dịch thất bại! Lỗi cú pháp JSON."
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

# Ráp link cho VLESS WS TLS
generate_vless_ws_tls_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local domain="$5"
    local ws_path="$6"
    
    local link="vless://${uuid}@${address}:${port}?encryption=none&security=tls&sni=${domain}&type=ws&path=${ws_path}#${tag}"
    
    echo "$link"
}

# Ráp link cho Hysteria2
generate_hysteria2_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local password="$4"
    local domain="$5"
    
    local link="hysteria2://${password}@${address}:${port}?sni=${domain}#${tag}"
    
    echo "$link"
}

# Ráp link cho TUIC
generate_tuic_link() {
    local tag="$1"
    local address="$2"
    local port="$3"
    local uuid="$4"
    local password="$5"
    local domain="$6"
    
    local link="tuic://${uuid}:${password}@${address}:${port}?congestion_control=bbr&sni=${domain}&alpn=h3#${tag}"
    
    echo "$link"
}