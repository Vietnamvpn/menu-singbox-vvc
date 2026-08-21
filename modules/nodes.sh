#!/bin/bash

NODES_FILE="$INSTALL_DIR/data/nodes.json"
mkdir -p "$INSTALL_DIR/data"

if [ ! -f "$NODES_FILE" ]; then
    echo "[]" > "$NODES_FILE"
fi

# ====================================================================
# CÁC HÀM PHỤ TRỢ (HELPER) KIỂM TRA VÀ TỰ ĐỘNG TẠO DỮ LIỆU
# ====================================================================

# Kiểm tra port đã sử dụng trong config hoặc đang mở trên hệ thống chưa
check_port_usage() {
    local check_port=$1
    # Kiểm tra trong cấu hình nodes.json
    if grep -q "\"port\": *$check_port\b" "$NODES_FILE" 2>/dev/null; then
        return 1 # Đã dùng
    fi
    # Kiểm tra port đang nghe trên hệ thống
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -qE ":$check_port\b"; then
            return 1 # Đã dùng
        fi
    elif command -v netstat >/dev/null 2>&1; then
         if netstat -tuln | grep -qE ":$check_port\b"; then
            return 1 # Đã dùng
         fi
    fi
    return 0 # Trống (Chưa sử dụng)
}

# Lấy một port ngẫu nhiên chưa ai dùng
get_random_port() {
    while true; do
        local rand_port=$((RANDOM % 4001 + 2000))
        if check_port_usage "$rand_port"; then
            echo "$rand_port"
            return
        fi
    done
}

# Tự động mở port trên các loại tường lửa phổ biến
open_firewall_port() {
    local port=$1
    echo -e "${YELLOW} Đang kiểm tra và mở port $port trên tường lửa...${NC}"
    
    # UFW (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port"/tcp >/dev/null 2>&1
        ufw allow "$port"/udp >/dev/null 2>&1
    fi
    # iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
    # firewalld (CentOS/Alma/Rocky)
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --add-port="${port}/udp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    echo -e "${GREEN} -> Đã mở port $port thành công.${NC}"
}

# Xử lý vòng lặp bắt buộc nhập/tạo Port hợp lệ
ASKED_PORT=""
ask_port() {
    while true; do
        read -p " Nhập Port [Để trống = ngẫu nhiên 2000-6000]: " ASKED_PORT
        if [ -z "$ASKED_PORT" ]; then
            ASKED_PORT=$(get_random_port)
            echo -e "${GREEN} -> Đã chọn Port ngẫu nhiên chưa sử dụng: $ASKED_PORT${NC}"
            break
        elif ! [[ "$ASKED_PORT" =~ ^[0-9]+$ ]] || [ "$ASKED_PORT" -lt 1 ] || [ "$ASKED_PORT" -gt 65535 ]; then
            echo -e "${RED}Lỗi: Port không hợp lệ, vui lòng nhập số từ 1-65535!${NC}"
        elif ! check_port_usage "$ASKED_PORT"; then
            echo -e "${RED}Lỗi: Port $ASKED_PORT đã có người dùng hoặc đang chạy ngầm, chọn port khác!${NC}"
        else
            break
        fi
    done
    open_firewall_port "$ASKED_PORT"
}

# Xử lý SNI
ASKED_SNI=""
ask_sni() {
    read -p " Nhập SNI (Server Name) [Để trống = tự tạo ngẫu nhiên]: " ASKED_SNI
    if [ -z "$ASKED_SNI" ]; then
        local snis=("itunes.apple.com" "www.microsoft.com" "www.bing.com" "update.microsoft.com" "gateway.icloud.com" "swdist.apple.com")
        local index=$((RANDOM % ${#snis[@]}))
        ASKED_SNI="${snis[$index]}"
        echo -e "${GREEN} -> Đã tự chọn SNI ngẫu nhiên: $ASKED_SNI${NC}"
    fi
}

# Xử lý Domain
ASKED_DOMAIN=""
ask_domain() {
    read -p " Nhập Tên miền (Domain) [Để trống = tự tạo ngẫu nhiên]: " ASKED_DOMAIN
    if [ -z "$ASKED_DOMAIN" ]; then
        ASKED_DOMAIN="node-$((RANDOM % 90000 + 10000)).example.com"
        echo -e "${GREEN} -> Đã tạo Domain ảo ngẫu nhiên: $ASKED_DOMAIN${NC}"
        echo -e "${YELLOW} Lưu ý: Bạn cần cấp chứng chỉ thực cho Domain này sau nếu dùng TLS.${NC}"
    fi
}

# Xử lý Private Key Reality
ASKED_PK=""
ask_private_key() {
    read -p " Nhập Private Key [Để trống = tự tạo ngẫu nhiên]: " ASKED_PK
    if [ -z "$ASKED_PK" ]; then
        if command -v sing-box &> /dev/null; then
            local kp=$(sing-box generate reality-keypair)
            ASKED_PK=$(echo "$kp" | grep "PrivateKey" | awk '{print $2}')
            echo -e "${GREEN} -> Đã tự tạo Private Key bằng sing-box core.${NC}"
        else
            ASKED_PK=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 43)
            echo -e "${GREEN} -> Đã tạo Private Key ngẫu nhiên thay thế.${NC}"
        fi
    fi
}

# Xử lý Short ID Reality
ASKED_SHORT_ID=""
ask_short_id() {
    read -p " Nhập Short ID [Để trống = tự tạo ngẫu nhiên]: " ASKED_SHORT_ID
    if [ -z "$ASKED_SHORT_ID" ]; then
        if command -v openssl >/dev/null 2>&1; then
            ASKED_SHORT_ID=$(openssl rand -hex 4)
        else
            ASKED_SHORT_ID=$(tr -dc 'a-f0-9' </dev/urandom | head -c 8)
        fi
        echo -e "${GREEN} -> Đã tạo Short ID ngẫu nhiên: $ASKED_SHORT_ID${NC}"
    fi
}

# Hàm kiểm tra trùng lặp Tag
check_tag_exists() {
    local tag_to_check=$1
    if grep -q "\"tag\": \"$tag_to_check\"" "$NODES_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Node với tag '$tag_to_check' đã tồn tại! Hủy bỏ thao tác.${NC}"
        sleep 2
        return 1
    fi
    return 0
}

# ====================================================================
# MENU VÀ GIAO DIỆN QUẢN LÝ
# ====================================================================

# Hiển thị danh sách Node
list_nodes() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                    DANH SÁCH NODE HIỆN TẠI                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    
    if [ ! -s "$NODES_FILE" ] || [ "$(cat "$NODES_FILE")" = "[]" ]; then
        echo -e "${YELLOW}Chưa có node nào được tạo.${NC}"
    else
        if command -v jq &> /dev/null; then
            jq -r '.[] | "Tag: \(.tag) │ Type: \(.type) │ Port: \(.port) │ Domain/SNI: \(.sni // .domain // "N/A")"' "$NODES_FILE"
        else
            cat "$NODES_FILE"
        fi
    fi
    echo -e "${CYAN}================================================================${NC}"
}

# Form 1: VLESS REALITY (TCP)
form_vless_reality() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}             THÊM NODE: VLESS REALITY (TCP)                    ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    
    ask_port
    ask_sni
    ask_private_key
    ask_short_id

    local tag="inbound-vless-reality-${ASKED_PORT}"
    check_tag_exists "$tag" || return

    jq --arg tag "$tag" \
       --arg type "vless-reality" \
       --argjson port "$ASKED_PORT" \
       --arg sni "$ASKED_SNI" \
       --arg private_key "$ASKED_PK" \
       --arg short_id "$ASKED_SHORT_ID" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "sni": $sni,
           "private_key": $private_key,
           "short_id": $short_id
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS REALITY thành công! Tag: $tag${NC}"
    sleep 2
}

# Form 2: VLESS WebSocket TLS
form_vless_ws_tls() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}             THÊM NODE: VLESS WEBSOCKET TLS                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"

    ask_port
    ask_domain

    read -p " Nhập WS Path [Để trống = tự tạo]: " ws_path
    if [ -z "$ws_path" ]; then
        ws_path="/ws-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
        echo -e "${GREEN} -> Đã tạo WS Path ngẫu nhiên: $ws_path${NC}"
    fi

    read -p " Nhập đường dẫn Certificate [Để trống = mặc định]: " cert_path
    cert_path="${cert_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/cert.pem}"

    read -p " Nhập đường dẫn Key [Để trống = mặc định]: " key_path
    key_path="${key_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/key.pem}"

    local tag="inbound-vless-ws-tls-${ASKED_PORT}"
    check_tag_exists "$tag" || return

    jq --arg tag "$tag" \
       --arg type "vless-ws-tls" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg ws_path "$ws_path" \
       --arg cert_path "$cert_path" \
       --arg key_path "$key_path" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "ws_path": $ws_path,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS WS TLS thành công! Tag: $tag${NC}"
    sleep 2
}

# Form 3: VLESS gRPC REALITY
form_vless_grpc_reality() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}             THÊM NODE: VLESS gRPC REALITY                    ${NC}"
    echo -e "${CYAN}================================================================${NC}"

    ask_port
    
    read -p " Nhập gRPC Service Name [Để trống = tự tạo]: " grpc_service
    if [ -z "$grpc_service" ]; then
        grpc_service="grpc-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
        echo -e "${GREEN} -> Đã tạo gRPC Service ngẫu nhiên: $grpc_service${NC}"
    fi

    ask_sni
    ask_private_key
    ask_short_id

    local tag="inbound-vless-grpc-reality-${ASKED_PORT}"
    check_tag_exists "$tag" || return

    jq --arg tag "$tag" \
       --arg type "vless-grpc-reality" \
       --argjson port "$ASKED_PORT" \
       --arg grpc_service "$grpc_service" \
       --arg sni "$ASKED_SNI" \
       --arg private_key "$ASKED_PK" \
       --arg short_id "$ASKED_SHORT_ID" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "grpc_service": $grpc_service,
           "sni": $sni,
           "private_key": $private_key,
           "short_id": $short_id
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS gRPC REALITY thành công! Tag: $tag${NC}"
    sleep 2
}

# Form 4: Hysteria 2
form_hy2() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                 THÊM NODE: HYSTERIA 2                         ${NC}"
    echo -e "${CYAN}================================================================${NC}"

    ask_port
    ask_domain
    
    read -p " Nhập tốc độ Upload (UP_MBPS) [Để trống = mặc định 100]: " up_mbps
    up_mbps="${up_mbps:-100}"
    
    read -p " Nhập tốc độ Download (DOWN_MBPS) [Để trống = mặc định 100]: " down_mbps
    down_mbps="${down_mbps:-100}"

    read -p " Nhập đường dẫn Certificate [Để trống = mặc định]: " cert_path
    cert_path="${cert_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/cert.pem}"

    read -p " Nhập đường dẫn Key [Để trống = mặc định]: " key_path
    key_path="${key_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/key.pem}"

    local tag="inbound-hy2-${ASKED_PORT}"
    check_tag_exists "$tag" || return

    jq --arg tag "$tag" \
       --arg type "hysteria2" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg up_mbps "$up_mbps" \
       --arg down_mbps "$down_mbps" \
       --arg cert_path "$cert_path" \
       --arg key_path "$key_path" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "up_mbps": $up_mbps,
           "down_mbps": $down_mbps,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node Hysteria 2 thành công! Tag: $tag${NC}"
    sleep 2
}

# Form 5: TUIC
form_tuic() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                     THÊM NODE: TUIC                           ${NC}"
    echo -e "${CYAN}================================================================${NC}"

    ask_port
    ask_domain

    read -p " Nhập đường dẫn Certificate [Để trống = mặc định]: " cert_path
    cert_path="${cert_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/cert.pem}"

    read -p " Nhập đường dẫn Key [Để trống = mặc định]: " key_path
    key_path="${key_path:-$INSTALL_DIR/certs/$ASKED_DOMAIN/key.pem}"

    local tag="inbound-tuic-${ASKED_PORT}"
    check_tag_exists "$tag" || return

    jq --arg tag "$tag" \
       --arg type "tuic" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg cert_path "$cert_path" \
       --arg key_path "$key_path" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node TUIC thành công! Tag: $tag${NC}"
    sleep 2
}

# Sub-Menu Thêm Node
add_node_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================================================${NC}"
        echo -e "${BLUE}                   CHỌN GIAO THỨC CHO NODE                     ${NC}"
        echo -e "${CYAN}================================================================${NC}"
        echo -e " ${GREEN}1.${NC} VLESS REALITY (TCP)"
        echo -e " ${GREEN}2.${NC} VLESS WebSocket TLS"
        echo -e " ${GREEN}3.${NC} VLESS gRPC REALITY"
        echo -e " ${GREEN}4.${NC} Hysteria 2"
        echo -e " ${GREEN}5.${NC} TUIC"
        echo -e " ${RED}0.${NC} Quay lại"
        echo -e "${CYAN}================================================================${NC}"
        read -p " Vui lòng chọn giao thức [0-5]: " proto_choice

        case $proto_choice in
            1) form_vless_reality ;;
            2) form_vless_ws_tls ;;
            3) form_vless_grpc_reality ;;
            4) form_hy2 ;;
            5) form_tuic ;;
            0) break ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; sleep 1 ;;
        esac
    done
}

# Xóa Node
delete_node() {
    clear
    list_nodes
    read -p " Nhập Tag của node cần xóa: " node_tag
    if [ -z "$node_tag" ]; then return; fi

    if command -v jq &> /dev/null; then
        jq --arg tag "$node_tag" '[.[] | select(.tag != $tag)]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"
        echo -e "${GREEN}Đã xóa node có tag: $node_tag${NC}"
        echo -e "${YELLOW}(Lưu ý: Tường lửa không được đóng tự động để tránh xung đột hệ thống)${NC}"
    else
        echo -e "${RED}Thiếu công cụ jq để xử lý JSON.${NC}"
    fi
    sleep 2
}

# Menu chính của module
while true; do
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}                     QUẢN LÝ THÔNG TIN NODE                   ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e " ${GREEN}1.${NC} Hiển thị danh sách Node"
    echo -e " ${GREEN}2.${NC} Thêm Node mới"
    echo -e " ${GREEN}3.${NC} Xóa Node"
    echo -e " ${RED}0.${NC} Quay lại Menu chính"
    echo -e "${CYAN}================================================================${NC}"
    read -p " Vui lòng chọn chức năng [0-3]: " choice

    case $choice in
        1)
            list_nodes
            read -n 1 -s -r -p "Nhấn phím bất kỳ để tiếp tục..."
            ;;
        2)
            add_node_menu
            ;;
        3)
            delete_node
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            sleep 1
            ;;
    esac
done