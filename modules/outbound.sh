#!/bin/bash

INSTALL_DIR="/opt/menu-singbox-vvc"
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
fi

OUTBOUND_FILE="${INSTALL_DIR}/data/outbound.json"

mkdir -p "$(dirname "$OUTBOUND_FILE")"
[ ! -f "$OUTBOUND_FILE" ] && echo "[]" > "$OUTBOUND_FILE"

# Menu quản lý Outbound & Relay
render_outbound_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${BLUE}||${NC}                  ${YELLOW}QUẢN LÝ OUTBOUND & RELAY                  ${BLUE}||${NC}"
        echo -e "${BLUE}================================================================${NC}"
        list_outbounds_table
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${GREEN}1.${NC} Thêm Link Outbound"
        echo -e " ${GREEN}2.${NC} Sửa Link Outbound"
        echo -e " ${GREEN}3.${NC} Xóa Link Outbound"
        echo -e " ${RED}0.${NC} Quay lại Menu Chính"
        echo -e "${CYAN}================================================================${NC}"
        read -p " Vui lòng chọn một chức năng [0-3]: " choice

        case "$choice" in
            1)
                add_outbound_from_link
                ;;
            2)
                edit_outbound
                ;;
            3)
                delete_outbound
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

# Hiển thị bảng danh sách outbound
list_outbounds_table() {
    echo -e " ${CYAN}Danh sách Outbound hiện tại:${NC}"
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e " ${YELLOW}(Chưa có outbound nào được cấu hình)${NC}"
        return
    fi
    
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    printf "${CYAN}%-4s${NC} | ${GREEN}%-20s${NC} | ${YELLOW}%-12s${NC} | ${BLUE}%-20s${NC}\n" "STT" "Tag" "Loại (Type)" "Địa chỉ:Cổng"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    
    local count
    count=$(jq length "$OUTBOUND_FILE")
    for ((i=0; i<count; i++)); do
        local tag type server port
        tag=$(jq -r --argjson idx "$i" '.[$idx].tag // "N/A"' "$OUTBOUND_FILE")
        type=$(jq -r --argjson idx "$i" '.[$idx].type // "N/A"' "$OUTBOUND_FILE")
        server=$(jq -r --argjson idx "$i" '.[$idx].server // "N/A"' "$OUTBOUND_FILE")
        port=$(jq -r --argjson idx "$i" '.[$idx].server_port // .[$idx].port // "N/A"' "$OUTBOUND_FILE")
        printf "%-4d | %-20s | %-12s | %-20s\n" "$((i+1))" "$tag" "$type" "$server:$port"
    done
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
}

# Thêm outbound từ link chia sẻ (Hỗ trợ giới hạn 3 giao thức: tuic, hy2/hysteria2, vless)
add_outbound_from_link() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} THÊM OUTBOUND TỪ LINK CHIA SẺ${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    read -p "Dán link chia sẻ (vless://, hy2://, tuic://): " link
    if [ -z "$link" ]; then
        echo -e "${RED}[LỖI] Link không được để trống!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local outbound_json
    outbound_json=$(python3 -c '
import sys
import urllib.parse
import json
import time

link = sys.argv[1]
try:
    parsed = urllib.parse.urlparse(link)
    scheme = parsed.scheme.lower()
    
    proto_map = {
        "hy2": "hysteria2",
        "hysteria2": "hysteria2",
        "vless": "vless",
        "tuic": "tuic"
    }
    out_type = proto_map.get(scheme)
    if not out_type:
        print(json.dumps({"error": "Hệ thống tạm thời chỉ hỗ trợ 3 giao thức: tuic, hy2, vless"}))
        sys.exit(0)
    
    tag = ""
    if parsed.fragment:
        tag = urllib.parse.unquote(parsed.fragment)
    else:
        tag = f"node_{int(time.time())}"
        
    hostname = parsed.hostname
    port = parsed.port or 443
    if not hostname:
        print(json.dumps({"error": "Không thể xác định địa chỉ server từ link"}))
        sys.exit(0)
        
    query = urllib.parse.parse_qs(parsed.query)
    def get_q(key, default=""):
        return query.get(key, [default])[0]

    outbound = {
        "type": out_type,
        "tag": tag,
        "server": hostname,
        "server_port": int(port)
    }

    # Xử lý bóc tách thông tin xác thực an toàn (hỗ trợ mã hóa %3A)
    userinfo = urllib.parse.unquote(parsed.netloc.rsplit("@", 1)[0]) if "@" in parsed.netloc else ""
    
    if out_type == "hysteria2":
        if userinfo:
            outbound["password"] = userinfo
        
        sni = get_q("sni") or get_q("peer") or hostname
        insecure = get_q("insecure") == "1" or get_q("allowInsecure") == "1" or get_q("allowinsecure") == "true"
        
        outbound["tls"] = {
            "enabled": True,
            "server_name": sni,
            "insecure": insecure
        }
        
        obfs = get_q("obfs")
        obfs_password = get_q("obfs-password") or get_q("obfs_password")
        if obfs:
            outbound["obfs"] = {
                "type": obfs,
                "password": obfs_password
            }
            
    elif out_type == "vless":
        if userinfo:
            outbound["uuid"] = userinfo
        
        sni = get_q("sni") or get_q("peer") or hostname
        security = get_q("security", "tls")
        insecure = get_q("insecure") == "1" or get_q("allowInsecure") == "1"
        fp = get_q("fp") or "chrome"
        
        if security == "reality":
            outbound["tls"] = {
                "enabled": True,
                "server_name": sni,
                "utls": {
                    "enabled": True,
                    "fingerprint": fp
                },
                "reality": {
                    "enabled": True,
                    "public_key": get_q("pbk"),
                    "short_id": get_q("sid")
                }
            }
        elif security == "tls":
            outbound["tls"] = {
                "enabled": True,
                "server_name": sni,
                "insecure": insecure
            }
            if fp:
                outbound["tls"]["utls"] = {
                    "enabled": True,
                    "fingerprint": fp
                }
            
        flow = get_q("flow")
        if flow:
            outbound["flow"] = flow
            
        # Xử lý transport (grpc, ws)
        net_type = get_q("type", "tcp")
        if net_type == "grpc":
            service_name = get_q("serviceName") or get_q("servicename")
            if service_name:
                outbound["transport"] = {
                    "type": "grpc",
                    "service_name": service_name
                }
        elif net_type == "ws":
            path = get_q("path") or "/"
            outbound["transport"] = {
                "type": "ws",
                "path": path
            }
            
    elif out_type == "tuic":
        if ":" in userinfo:
            uuid_val, pwd_val = userinfo.split(":", 1)
            outbound["uuid"] = uuid_val
            outbound["password"] = pwd_val
        else:
            outbound["uuid"] = userinfo
            
        sni = get_q("sni") or hostname
        insecure = get_q("insecure") == "1" or get_q("allowInsecure") == "1" or get_q("allowinsecure") == "true"
        congestion_control = get_q("congestion_control") or get_q("cc") or "bbr"
        
        outbound["tls"] = {
            "enabled": True,
            "server_name": sni,
            "insecure": insecure,
            "alpn": ["h3"]
        }
        outbound["congestion_control"] = congestion_control
            
    print(json.dumps(outbound))
except Exception as e:
    print(json.dumps({"error": str(e)}))
' "$link")

    if echo "$outbound_json" | jq -e '.error' >/dev/null 2>&1; then
        local err_msg
        err_msg=$(echo "$outbound_json" | jq -r '.error')
        echo -e "${RED}[LỖI] $err_msg${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local tag
    tag=$(echo "$outbound_json" | jq -r '.tag')

    local exists
    exists=$(jq --arg t "$tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
    if [ "$exists" -gt 0 ]; then
        tag="${tag}_$(date +%s)"
        outbound_json=$(echo "$outbound_json" | jq --arg t "$tag" '.tag = $t')
    fi

    jq --argjson new_node "$outbound_json" '. += [$new_node]' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"

    local type_val server_val port_val
    type_val=$(echo "$outbound_json" | jq -r '.type')
    server_val=$(echo "$outbound_json" | jq -r '.server')
    port_val=$(echo "$outbound_json" | jq -r '.server_port')

    log_success "Đã thêm outbound '$tag' (Loại: $type_val, Server: $server_val:$port_val) thành công!"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi
    
    read -p "Nhấn Enter để tiếp tục..."
}

# Sửa outbound hiện có
edit_outbound() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${YELLOW} SỬA OUTBOUND${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có outbound nào trong hệ thống để sửa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_outbounds_table
    read -p "Nhập số thứ tự (STT) của outbound cần sửa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$OUTBOUND_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) vượt quá giới hạn danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local old_tag old_type old_server old_port
    old_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$OUTBOUND_FILE")
    old_type=$(jq -r --argjson i "$idx" '.[$i].type' "$OUTBOUND_FILE")
    old_server=$(jq -r --argjson i "$idx" '.[$i].server // ""' "$OUTBOUND_FILE")
    old_port=$(jq -r --argjson i "$idx" '.[$i].server_port // .[$i].port // 0' "$OUTBOUND_FILE")

    echo -e "Đang sửa Outbound: ${CYAN}$old_tag${NC}"
    read -p "Nhập Tag mới [Mặc định: $old_tag]: " new_tag
    new_tag="${new_tag:-$old_tag}"

    if [ "$new_tag" != "$old_tag" ]; then
        local exists
        exists=$(jq --arg t "$new_tag" '[.[] | select(.tag == $t)] | length' "$OUTBOUND_FILE")
        if [ "$exists" -gt 0 ]; then
            echo -e "${RED}[LỖI] Tag '$new_tag' đã bị trùng với outbound khác!${NC}"
            read -p "Nhấn Enter để tiếp tục..."
            return
        fi
    fi

    read -p "Nhập Loại mới [Mặc định: $old_type]: " new_type
    new_type="${new_type:-$old_type}"

    read -p "Nhập Server mới [Mặc định: $old_server]: " new_server
    new_server="${new_server:-$old_server}"

    read -p "Nhập Cổng mới [Mặc định: $old_port]: " new_port
    new_port="${new_port:-$old_port}"

    if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] Cổng (Port) phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    jq --argjson i "$idx" --arg t "$new_tag" --arg tp "$new_type" --arg s "$new_server" --argjson p "$new_port" \
       '.[$i] = {"type": $tp, "tag": $t, "server": $s, "server_port": $p}' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"

    log_success "Đã cập nhật outbound thành công!"
    
    if declare -f build_and_apply_config > /dev/null; then
        build_and_apply_config
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Xóa outbound
delete_outbound() {
    echo -e "${CYAN}--------------------------------------------------${NC}"
    echo -e "${RED} XÓA OUTBOUND${NC}"
    echo -e "${CYAN}--------------------------------------------------${NC}"
    
    if [ ! -s "$OUTBOUND_FILE" ] || [ "$(jq length "$OUTBOUND_FILE" 2>/dev/null)" -eq 0 ]; then
        echo -e "${YELLOW}[CẢNH BÁO] Không có outbound nào để xóa.${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    list_outbounds_table
    read -p "Nhập số thứ tự (STT) của outbound cần xóa: " index_input

    if ! [[ "$index_input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[LỖI] STT phải là một số nguyên hợp lệ!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local idx=$((index_input - 1))
    local count
    count=$(jq length "$OUTBOUND_FILE")

    if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
        echo -e "${RED}[LỖI] Số thứ tự ($index_input) không tồn tại trong danh sách!${NC}"
        read -p "Nhấn Enter để tiếp tục..."
        return
    fi

    local target_tag
    target_tag=$(jq -r --argjson i "$idx" '.[$i].tag' "$OUTBOUND_FILE")

    read -p "Bạn có chắc chắn muốn xóa outbound '$target_tag' không? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        jq --argjson i "$idx" 'del(.[$i])' "$OUTBOUND_FILE" > "$OUTBOUND_FILE.tmp" && mv "$OUTBOUND_FILE.tmp" "$OUTBOUND_FILE"
        log_success "Đã xóa outbound '$target_tag' khỏi hệ thống!"
        
        if declare -f build_and_apply_config > /dev/null; then
            build_and_apply_config
        fi
    else
        echo "Đã hủy thao tác xóa."
    fi

    read -p "Nhấn Enter để tiếp tục..."
}

# Khởi chạy menu của module
render_outbound_menu