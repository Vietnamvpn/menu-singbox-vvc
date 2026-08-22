#!/bin/bash

# Khai báo đường dẫn gốc chính xác
INSTALL_DIR="/opt/menu-singbox-vvc"
NODES_FILE="$INSTALL_DIR/data/nodes.json"
mkdir -p "$INSTALL_DIR/data"

if [ ! -f "$NODES_FILE" ]; then
    echo "[]" > "$NODES_FILE"
fi

# Nhúng màu sắc và các hàm tiện ích dùng chung từ utils.sh
if [ -f "$INSTALL_DIR/modules/utils.sh" ]; then
    source "$INSTALL_DIR/modules/utils.sh"
else
    echo "Lỗi: Không tìm thấy file utils.sh tại $INSTALL_DIR/modules/"
    exit 1
fi

# ====================================================================
# CÁC HÀM PHỤ TRỢ (HELPER) KIỂM TRA VÀ TỰ ĐỘNG TẠO DỮ LIỆU
# ====================================================================

# Kiểm tra port đã sử dụng trong config hoặc đang mở trên hệ thống chưa
check_port_usage() {
    local check_port=$1
    if grep -q "\"port\": *$check_port\b" "$NODES_FILE" 2>/dev/null; then
        return 1
    fi
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -qE ":$check_port\b"; then
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
         if netstat -tuln | grep -qE ":$check_port\b"; then
            return 1
         fi
    fi
    return 0
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

# Tự động mở port trên các loại tường lửa
open_firewall_port() {
    local port=$1
    echo -e "${YELLOW} Đang kiểm tra và mở port $port trên tường lửa...${NC}"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$port"/tcp >/dev/null 2>&1
        ufw allow "$port"/udp >/dev/null 2>&1
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port="${port}/tcp" --permanent >/dev/null 2>&1
        firewall-cmd --add-port="${port}/udp" --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    echo -e "${GREEN} -> Đã mở port $port thành công.${NC}"
}

# 1. Form nhập Port
ASKED_PORT=""
ask_port() {
    while true; do
        read -p " Nhập Port [Để trống = ngẫu nhiên 2000-6000]: " ASKED_PORT
        if [ -z "$ASKED_PORT" ]; then
            ASKED_PORT=$(get_random_port)
            echo -e "${GREEN} -> Đã chọn Port ngẫu nhiên chưa sử dụng: $ASKED_PORT${NC}"
            break
        elif ! [[ "$ASKED_PORT" =~ ^[0-9]+$ ]] || [ "$ASKED_PORT" -lt 1 ] || [ "$ASKED_PORT" -gt 65535 ]; then
            echo -e "${RED}Lỗi: Port không hợp lệ!${NC}"
        elif ! check_port_usage "$ASKED_PORT"; then
            echo -e "${RED}Lỗi: Port $ASKED_PORT đã có người dùng, chọn port khác!${NC}"
        else
            break
        fi
    done
    open_firewall_port "$ASKED_PORT"
}

# 2. Form nhập SNI
ASKED_SNI=""
ask_sni() {
    read -p " Nhập SNI (Server Name) [Để trống = tự tạo ngẫu nhiên]: " ASKED_SNI
    if [ -z "$ASKED_SNI" ]; then
        local snis=("itunes.apple.com" "www.microsoft.com" "www.bing.com" "update.microsoft.com" "gateway.icloud.com")
        local index=$((RANDOM % ${#snis[@]}))
        ASKED_SNI="${snis[$index]}"
        echo -e "${GREEN} -> Đã tự chọn SNI ngẫu nhiên: $ASKED_SNI${NC}"
    fi
}

# 3. Form nhập Domain (Linh hoạt lấy theo IP, Port, SNI nếu trống)
ASKED_DOMAIN=""
ask_domain() {
    read -p " Nhập Tên miền (Domain) [Để trống = tự tạo theo IP/SNI]: " ASKED_DOMAIN
    if [ -z "$ASKED_DOMAIN" ]; then
        local ip=$(curl -s4 ifconfig.me || echo "127.0.0.1")
        if [ -n "$ASKED_SNI" ]; then
            ASKED_DOMAIN="$ASKED_SNI"
        else
            ASKED_DOMAIN="${ip}.nip.io"
        fi
        echo -e "${GREEN} -> Đã tạo Domain tự động: $ASKED_DOMAIN${NC}"
    fi
}

# 4. Form nhập Tag
ASKED_TAG=""
ask_tag() {
    local default_prefix=$1
    read -p " Nhập Tag cho Node [Để trống = ngẫu nhiên]: " ASKED_TAG
    if [ -z "$ASKED_TAG" ]; then
        ASKED_TAG="${default_prefix}-${ASKED_PORT}-$((RANDOM % 9000 + 1000))"
        echo -e "${GREEN} -> Đã tạo Tag tự động: $ASKED_TAG${NC}"
    fi
}

# 5. Form nhập Chứng chỉ
ASKED_CERT=""
ASKED_KEY=""
ask_cert() {
    read -p " Nhập đường dẫn Certificate [Để trống = dùng mặc định của hệ thống]: " ASKED_CERT
    ASKED_CERT="${ASKED_CERT:-$INSTALL_DIR/certs/default/cert.pem}"
    
    read -p " Nhập đường dẫn Private Key [Để trống = dùng mặc định của hệ thống]: " ASKED_KEY
    ASKED_KEY="${ASKED_KEY:-$INSTALL_DIR/certs/default/private.key}"
    
    echo -e "${GREEN} -> Cert: $ASKED_CERT${NC}"
    echo -e "${GREEN} -> Key: $ASKED_KEY${NC}"
}

# Hàm kiểm tra trùng lặp Tag
check_tag_exists() {
    if grep -q "\"tag\": \"$ASKED_TAG\"" "$NODES_FILE" 2>/dev/null; then
        echo -e "${RED}Lỗi: Node với tag '$ASKED_TAG' đã tồn tại! Hủy bỏ thao tác.${NC}"
        sleep 2
        return 1
    fi
    return 0
}

# ====================================================================
# CÁC HÀM AUTO-GENERATE (KHÔNG CẦN FORM NHẬP)
# ====================================================================

AUTO_PK=""
generate_private_key() {
    if command -v sing-box &> /dev/null; then
        local kp=$(sing-box generate reality-keypair)
        AUTO_PK=$(echo "$kp" | grep "PrivateKey" | awk '{print $2}')
    else
        AUTO_PK=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 43)
    fi
    echo -e "${GREEN} -> Đã tự động tạo Private Key.${NC}"
}

AUTO_SHORT_ID=""
generate_short_id() {
    if command -v openssl >/dev/null 2>&1; then
        AUTO_SHORT_ID=$(openssl rand -hex 4)
    else
        AUTO_SHORT_ID=$(tr -dc 'a-f0-9' </dev/urandom | head -c 8)
    fi
    echo -e "${GREEN} -> Đã tự động tạo Short ID: $AUTO_SHORT_ID${NC}"
}

AUTO_UUID=""
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        AUTO_UUID=$(uuidgen)
    else
        AUTO_UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    echo -e "${GREEN} -> Đã tự động tạo UUID.${NC}"
}

AUTO_PASS=""
generate_password() {
    AUTO_PASS=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)
    echo -e "${GREEN} -> Đã tự động tạo Password.${NC}"
}

# ====================================================================
# MENU VÀ GIAO DIỆN QUẢN LÝ
# ====================================================================

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
    ask_tag "vless-reality"
    
    check_tag_exists || return

    generate_private_key
    generate_short_id

    jq --arg tag "$ASKED_TAG" \
       --arg type "vless-reality" \
       --argjson port "$ASKED_PORT" \
       --arg sni "$ASKED_SNI" \
       --arg private_key "$AUTO_PK" \
       --arg short_id "$AUTO_SHORT_ID" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "sni": $sni,
           "private_key": $private_key,
           "short_id": $short_id
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS REALITY thành công! Tag: $ASKED_TAG${NC}"
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
    ask_cert
    ask_tag "vless-ws-tls"
    
    check_tag_exists || return

    local auto_ws_path="/ws-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    echo -e "${GREEN} -> Đã tự động tạo WS Path: $auto_ws_path${NC}"

    jq --arg tag "$ASKED_TAG" \
       --arg type "vless-ws-tls" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg ws_path "$auto_ws_path" \
       --arg cert_path "$ASKED_CERT" \
       --arg key_path "$ASKED_KEY" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "ws_path": $ws_path,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS WS TLS thành công! Tag: $ASKED_TAG${NC}"
    sleep 2
}

# Form 3: VLESS gRPC REALITY
form_vless_grpc_reality() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${BLUE}             THÊM NODE: VLESS gRPC REALITY                    ${NC}"
    echo -e "${CYAN}================================================================${NC}"

    ask_port
    ask_sni
    ask_tag "vless-grpc-reality"
    
    check_tag_exists || return

    local auto_grpc="grpc-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
    echo -e "${GREEN} -> Đã tự động tạo gRPC Service: $auto_grpc${NC}"
    
    generate_private_key
    generate_short_id

    jq --arg tag "$ASKED_TAG" \
       --arg type "vless-grpc-reality" \
       --argjson port "$ASKED_PORT" \
       --arg grpc_service "$auto_grpc" \
       --arg sni "$ASKED_SNI" \
       --arg private_key "$AUTO_PK" \
       --arg short_id "$AUTO_SHORT_ID" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "grpc_service": $grpc_service,
           "sni": $sni,
           "private_key": $private_key,
           "short_id": $short_id
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node VLESS gRPC REALITY thành công! Tag: $ASKED_TAG${NC}"
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
    ask_cert
    ask_tag "hy2"
    
    check_tag_exists || return

    generate_password
    local auto_up_mbps="100"
    local auto_down_mbps="100"
    echo -e "${GREEN} -> Đã tự động gán tốc độ UP/DOWN mặc định là 100 Mbps.${NC}"

    jq --arg tag "$ASKED_TAG" \
       --arg type "hysteria2" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg password "$AUTO_PASS" \
       --arg up_mbps "$auto_up_mbps" \
       --arg down_mbps "$auto_down_mbps" \
       --arg cert_path "$ASKED_CERT" \
       --arg key_path "$ASKED_KEY" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "password": $password,
           "up_mbps": $up_mbps,
           "down_mbps": $down_mbps,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node Hysteria 2 thành công! Tag: $ASKED_TAG${NC}"
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
    ask_cert
    ask_tag "tuic"
    
    check_tag_exists || return

    generate_uuid
    generate_password

    jq --arg tag "$ASKED_TAG" \
       --arg type "tuic" \
       --argjson port "$ASKED_PORT" \
       --arg domain "$ASKED_DOMAIN" \
       --arg uuid "$AUTO_UUID" \
       --arg password "$AUTO_PASS" \
       --arg cert_path "$ASKED_CERT" \
       --arg key_path "$ASKED_KEY" \
       '. += [{
           "tag": $tag,
           "type": $type,
           "port": $port,
           "domain": $domain,
           "uuid": $uuid,
           "password": $password,
           "cert_path": $cert_path,
           "key_path": $key_path
       }]' "$NODES_FILE" > "$NODES_FILE.tmp" && mv "$NODES_FILE.tmp" "$NODES_FILE"

    echo -e "${GREEN}Thêm Node TUIC thành công! Tag: $ASKED_TAG${NC}"
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