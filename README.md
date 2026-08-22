bash <(curl -Ls https://raw.githubusercontent.com/Vietnamvpn/menu-singbox-vvc/main/install.sh)

menu-singbox-vvc/
├── install.sh                  # Script cài đặt ban đầu (tải sing-box, thiết lập môi trường)
├── update.sh                   # Cập nhật phiên bản script/core
├── main.sh                     # Entry point cho CLI (chạy bằng lệnh vvc)
├── core/                       
│   └── api_server.go           # [HỢP NHẤT] Daemon xử lý tập trung: Giao tiếp API, Push traffic, Fetch users và tính toán dung lượng.
├── modules/                    
│   ├── system.sh               # Quản lý service (start/stop/restart), firewall
│   ├── nodes.sh                # Quản lý thông tin và cấu hình Node
│   ├── entry-node.sh           # Thêm/sửa/xóa cổng, domain entry theo tag
│   ├── users.sh                # Logic thêm/sửa/xóa/khóa user (CLI)
│   ├── outbound.sh             # Node relay
│   ├── routing.sh              # Quy tắc đầu ra
│   ├── ssl.sh                  # Xin chứng chỉ Cloudflare
│   ├── api-web.sh              # Xử lý API gọi lên web trung tâm (Chỉ dùng cho các lệnh thủ công tức thời từ CLI)
│   └── utils.sh                # Tiện ích chung (parse JSON, random port...)
├── data/                       
│   ├── nodes.json              # Lưu trữ thông tin Node
│   ├── users.json              # Lưu trữ thông tin user
│   ├── outbound.json           # Lưu trữ thông tin Node relay
│   ├── routing.json            # Lưu trữ thông tin Quy tắc đầu ra
│   ├── domain.json             # Lưu trữ thông tin theo tag node
│   ├── entry-node.json         # Lưu trữ thông tin cổng, domain entry theo tag
│   └── local_state.json        # Cache dữ liệu (tránh xung đột ghi)
├── certs/                      # [MỚI] Thư mục chuẩn hóa chuyên chứa chứng chỉ SSL (vd: certs/domain.com/)
├── logs/                       # [MỚI] Thư mục tập trung log của hệ thống (CLI log, Go Daemon log, Sing-box log)
└── templates/
    ├── config.base.json        
    ├── sing-box.service        
    ├── manager.service         
    ├── inbound_hy2.json
    ├── inbound_tuic.json
    └── vless/
        ├── vless-reality.json
        ├── vless-grpc-reality.json
        └── vless-ws-tls.json