## 🚀 CÀI ĐẶT NHANH

### 📋 Link Cài Đặt (Click Nút Bên Dưới để Copy)

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Vietnamvpn/menu-singbox-vvc/main/install.sh)
```

> **Hướng Dẫn Copy:**
> 1. Bôi đen toàn bộ lệnh trên
> 2. Nhấn `Ctrl + C` để copy
> 3. SSH vào server và dán lệnh
> 4. Nhấn Enter để bắt đầu cài đặt

---

## 📁 CẤU TRÚC THƯ MỤC DỰ ÁN

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
│   └── entry-node.json         # Lưu trữ thông tin cổng, domain entry theo tag
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

---

## 📖 HƯỚNG DẪN THAO TÁC CHI TIẾT

### 🎯 Menu Chính
Khi chạy lệnh `vvc`, bạn sẽ vào menu chính với các lựa chọn quản lý hệ thống.

---

### 1️⃣ QUẢN LÝ SING-BOX CORE (modules/system.sh)

**Menu Chính:** Điều khiển Sing-box Core

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Khởi Động Sing-box | Khởi động service Sing-box nếu chưa chạy |
| 2 | Dừng Sing-box | Dừng service Sing-box |
| 3 | Khởi Động Lại Sing-box | Restart service Sing-box (hữu ích khi cập nhật cấu hình) |
| 4 | Cập Nhật Sing-box Core Mới Nhất | Nâng cấp Sing-box core lên phiên bản mới nhất từ repository |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Trạng thái hiển thị:** Trạng thái core và phiên bản hiện tại được hiển thị ở đầu menu

---

### 2️⃣ QUẢN LÝ NODE INBOUND (modules/nodes.sh)

**Menu Chính:** Quản lý Node (Inbound)

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Thêm Node Inbound | Tạo node inbound mới (hỗ trợ: VLESS Reality, VLESS WS-TLS, Hysteria2, TUIC) |
| 2 | Sửa Node Inbound | Chỉnh sửa cấu hình node đã tạo |
| 3 | Xóa Node Inbound | Xóa node khỏi hệ thống |
| 4 | Xem Chi Tiết Node | Hiển thị thông tin chi tiết của từng node |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Thông tin được lưu:** Tag, Type (loại protocol), Port, Domain/SNI, và các cấu hình khác theo protocol

---

### 3️⃣ QUẢN LÝ NGƯỜI DÙNG (modules/users.sh)

**Menu Chính:** Quản lý User

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Thêm User Mới | Tạo tài khoản user mới (tự động sinh UUID) |
| 2 | Xem Danh Sách User | Hiển thị danh sách tất cả user, trạng thái và dung lượng sử dụng |
| 3 | Xem Link Kết Nối | Hiển thị link chia sẻ (share link) cho từng user |
| 4 | Sửa Thông Tin User | Chỉnh sửa username, tag, hoặc thông tin khác |
| 5 | Xóa User | Xóa tài khoản user khỏi hệ thống |
| 6 | Khóa/Mở Khóa User | Vô hiệu hóa hoặc kích hoạt lại tài khoản user |
| 7 | Đặt Lại Dung Lượng | Cấp lại dung lượng cho user |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Thông tin hiển thị:** Username, Tag, UUID, Status (active/inactive), Dung lượng đã sử dụng

---

### 4️⃣ QUẢN LÝ ENTRY NODE (modules/entry-node.sh)

**Menu Chính:** Quản lý Entry Node (Cấp Link)

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Thêm Entry Node | Thêm cổng và domain entry mới (liên kết với một node inbound) |
| 2 | Sửa Entry Node | Cập nhật thông tin cổng hoặc domain entry |
| 3 | Xóa Entry Node | Xóa entry node khỏi hệ thống |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Thông tin được lưu:** Tên Entry, Địa chỉ (IP/Domain), Cổng, Liên kết Node (node_tag)

**Lưu ý:** Entry node là cổng vào cho user kết nối, được liên kết với một node inbound cụ thể

---

### 5️⃣ QUẢN LÝ OUTBOUND & RELAY (modules/outbound.sh)

**Menu Chính:** Quản lý Outbound & Relay

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Thêm Link Outbound | Thêm outbound relay từ link chia sẻ (hỗ trợ: VLESS, Hysteria2, TUIC) |
| 2 | Sửa Link Outbound | Chỉnh sửa thông tin outbound |
| 3 | Xóa Link Outbound | Xóa outbound khỏi hệ thống |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Thông tin được lưu:** Tag, Type (loại protocol), Địa chỉ server:cổng

**Lưu ý:** Outbound dùng để relay traffic qua các node khác (giống như VPN chained)

---

### 6️⃣ QUẢN LÝ ĐỊNH TUYẾN (modules/routing.sh)

**Menu Chính:** Quản lý Định Tuyến (Routing)

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Thêm Quy Tắc Định Tuyến | Tạo quy tắc định hướng traffic từ inbound đến outbound |
| 2 | Sửa Quy Tắc Định Tuyến | Chỉnh sửa quy tắc routing đã tạo |
| 3 | Xóa Quy Tắc Định Tuyến | Xóa quy tắc khỏi hệ thống |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Thông tin được lưu:** Inbound Tag (cổng vào), Outbound Tag (cổng ra)

**Lưu ý:** Routing kết nối inbound (cấp link cho user) với outbound (relay node)

---

### 7️⃣ QUẢN LÝ CHỨNG CHỈ SSL (modules/ssl.sh)

**Menu Chính:** Quản lý Chứng Chỉ SSL (Cloudflare)

| Mã | Chức Năng | Mô Tả |
|-----|----------|-------|
| 1 | Xin/Cập Nhật Chứng Chỉ SSL | Đăng ký hoặc gia hạn chứng chỉ SSL từ Cloudflare (sử dụng ACME.sh) |
| 2 | Xem Chi Tiết Chứng Chỉ | Hiển thị thông tin chi tiết chứng chỉ (tên miền, ngày hết hạn, v.v.) |
| 3 | Gỡ Bỏ Chứng Chỉ SSL | Xóa chứng chỉ SSL khỏi hệ thống |
| 0 | Quay Lại Menu Chính | Trở về menu chính |

**Yêu Cầu:** 
- Tên miền hợp lệ (có thể là sub-domain)
- Email tài khoản Cloudflare
- API Token hoặc Global API Key từ Cloudflare

**Thư Mục Lưu Trữ:** `/etc/sing-box/certs/`

---

### 8️⃣ XỬ LÝ API WEB (modules/api-web.sh)

**Mô Tả:** Module xử lý các lệnh API tương tác với web trung tâm quản lý

| Chức Năng | Mô Tả |
|----------|-------|
| Đẩy Traffic | Gửi thông tin traffic/dung lượng sử dụng từ daemon lên server web |
| Lấy Dữ Liệu User | Đồng bộ danh sách user từ server web về hệ thống local |
| Cập Nhật Cấu Hình | Lấy cấu hình mới nhất từ server quản lý |

**Lưu Ý:** Module này chủ yếu tương tác với daemon Go (`api_server.go`) và thường không cần thao tác thủ công

---

### 9️⃣ TIỆN ÍCH CHUNG (modules/utils.sh)

**Các hàm tiện ích hỗ trợ:**

| Hàm Tiện Ích | Mô Tả |
|------------|-------|
| `get_random_port()` | Sinh cổng ngẫu nhiên (2000-6000) không xung đột |
| `check_port_usage()` | Kiểm tra cổng đã được sử dụng |
| `open_firewall_port()` | Mở cổng trên tường lửa (UFW, iptables, firewall-cmd) |
| `close_firewall_port()` | Đóng cổng trên tường lửa |
| `parse_json()` | Phân tích file JSON |
| `generate_uuid()` | Sinh UUID mới cho user |

---

## 🔄 QUY TRÌNH THƯỜNG DÙNG

### Quy Trình 1: Tạo Node Mới và Cấp Link cho User
1. **Quản lý Node** → Thêm Node Inbound (chọn protocol: VLESS Reality, Hysteria2, v.v.)
2. **Quản lý Entry Node** → Thêm Entry Node (chọn cổng, domain liên kết với node vừa tạo)
3. **Quản lý User** → Thêm User Mới (tự động sinh UUID)
4. **Quản lý User** → Xem Link Kết Nối (lấy link chia sẻ cho user)

### Quy Trình 2: Thiết Lập Relay/Outbound
1. **Quản lý Outbound** → Thêm Link Outbound (dán link chia sẻ từ server khác)
2. **Quản lý Định Tuyến** → Thêm Quy Tắc Định Tuyến (chọn Inbound Entry → Outbound Relay)
3. **Quản lý Sing-box Core** → Khởi Động Lại Sing-box (áp dụng cấu hình)

### Quy Trình 3: Thiết Lập SSL cho VLESS WS-TLS
1. **Quản lý Chứng Chỉ SSL** → Xin/Cập Nhật Chứng Chỉ SSL (nhập tên miền, email, API key Cloudflare)
2. **Quản lý Node** → Thêm Node VLESS WS-TLS (chọn domain và port 443)
3. **Quản lý Sing-box Core** → Khởi Động Lại Sing-box

---

## 📝 GHI CHÚ QUAN TRỌNG

- **Dữ Liệu Lưu Trữ:** Tất cả thông tin được lưu trong thư mục `data/` dưới dạng JSON
- **Cấu Hình Tự Động:** Hệ thống tự động sinh cổng ngẫu nhiên và quản lý firewall
- **Daemon API Server:** `api_server.go` chạy liên tục để đồng bộ traffic, user, và cấu hình
- **Log Hệ Thống:** Các log được tập trung trong thư mục `logs/`
- **Chứng Chỉ SSL:** Lưu tại `/etc/sing-box/certs/` (hoặc thư mục `certs/` trong dự án)