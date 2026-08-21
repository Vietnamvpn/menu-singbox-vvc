package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

const (
	ListenAddr    = ":8080"
	DataDir       = "/opt/menu-singbox-vvc/data"
	CentralWebURL = "https://your-central-web.com/api" // Thay bằng URL API của web trung tâm
)

var (
	usersFile     = filepath.Join(DataDir, "users.json")
	entryNodeFile = filepath.Join(DataDir, "entry-node.json")
	fileMutex     sync.Mutex
)

// Dữ liệu User theo chuẩn file JSON
type User struct {
	Username string `json:"username"`
	UUID     string `json:"uuid,omitempty"`
	Password string `json:"password,omitempty"`
	Protocol string `json:"protocol"`
	Port     int    `json:"port"`
	Tag      string `json:"tag"`
}

// Request từ Web trung tâm gửi sang để reset
type ResetRequest struct {
	Username string `json:"username"`
}

// Response trả về Web trung tâm
type ResetResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	NewLink string `json:"new_link,omitempty"`
}

// Cấu trúc Entry Node để thay thế IP/Port trước khi trả link
type EntryNode struct {
	Tag    string `json:"tag"`
	Domain string `json:"domain"`
	Port   int    `json:"port"`
}

func main() {
	os.MkdirAll(DataDir, 0755)

	// 1. Chạy các tiến trình ngầm thay thế Cron
	go fetchUsersRoutine()
	go pushTrafficRoutine()

	// 2. Mở HTTP API Server chờ lệnh từ Web trung tâm
	http.HandleFunc("/api/reset-password", handleResetPassword)

	log.Printf("Sing-box Manager API Server đang chạy tại port %s", ListenAddr)
	if err := http.ListenAndServe(ListenAddr, nil); err != nil {
		log.Fatalf("Lỗi khởi động API server: %v", err)
	}
}

// ==========================================
// MODULE: NHẬN LỆNH RESET & TRẢ LINK
// ==========================================
func handleResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ResetRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSONResponse(w, "error", "Payload không hợp lệ", "")
		return
	}

	// Khoá file để tránh xung đột với CLI bash (race condition)
	fileMutex.Lock()
	defer fileMutex.Unlock()

	users, err := readUsers()
	if err != nil {
		sendJSONResponse(w, "error", "Lỗi đọc dữ liệu users", "")
		return
	}

	var foundUser *User
	for i := range users {
		if users[i].Username == req.Username {
			// Tạo dữ liệu mới tương ứng với giao thức
			if users[i].UUID != "" {
				users[i].UUID = generateUUID()
			}
			if users[i].Password != "" {
				users[i].Password = generateRandomString(16)
			}
			foundUser = &users[i]
			break
		}
	}

	if foundUser == nil {
		sendJSONResponse(w, "error", "Không tìm thấy User", "")
		return
	}

	// Ghi lại file với mật khẩu/UUID mới
	if err := writeUsers(users); err != nil {
		sendJSONResponse(w, "error", "Lỗi ghi dữ liệu mới", "")
		return
	}

	// Thay thế thông tin gốc bằng thông tin Entry Node và sinh Link
	newLink := generateProxyLink(*foundUser)

	// Gọi CLI build lại file config.json của sing-box và restart
	go reloadSingbox()

	// Trả kết quả thành công kèm link mới cho file PHP
	sendJSONResponse(w, "success", "Reset thành công", newLink)
}

// ==========================================
// MODULE: TIẾN TRÌNH NGẦM (BACKGROUND JOBS)
// ==========================================
func fetchUsersRoutine() {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		log.Println("Đang kiểm tra lệnh thêm/khóa user từ web trung tâm...")
		// Code gọi GET/POST tới API Web trung tâm
	}
}

func pushTrafficRoutine() {
	ticker := time.NewTicker(10 * time.Minute)
	for range ticker.C {
		log.Println("Đang đẩy đồng bộ thống kê dung lượng (Traffic) lên web...")
		// Code đọc stats từ sing-box và POST về web
	}
}

// ==========================================
// MODULE: TIỆN ÍCH (UTILITIES)
// ==========================================
func sendJSONResponse(w http.ResponseWriter, status, message, link string) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ResetResponse{
		Status:  status,
		Message: message,
		NewLink: link,
	})
}

func readUsers() ([]User, error) {
	data, err := ioutil.ReadFile(usersFile)
	if err != nil {
		if os.IsNotExist(err) {
			return []User{}, nil
		}
		return nil, err
	}
	var users []User
	err = json.Unmarshal(data, &users)
	return users, err
}

func writeUsers(users []User) error {
	data, err := json.MarshalIndent(users, "", "  ")
	if err != nil {
		return err
	}
	return ioutil.WriteFile(usersFile, data, 0644)
}

// Hàm lấy thông tin thay thế từ Entry Node trước khi đẩy ra
func getEntryNodeInfo(tag string, defaultPort int) (string, int) {
	data, err := ioutil.ReadFile(entryNodeFile)
	if err == nil {
		var entries []EntryNode
		if json.Unmarshal(data, &entries) == nil {
			for _, e := range entries {
				if e.Tag == tag {
					return e.Domain, e.Port
				}
			}
		}
	}
	return "VPS_IP_OR_DOMAIN", defaultPort // Dự phòng
}

func generateProxyLink(u User) string {
	domain, port := getEntryNodeInfo(u.Tag, u.Port)

	switch u.Protocol {
	case "vless":
		// Mẫu link chuẩn VLESS Reality
		return fmt.Sprintf("vless://%s@%s:%d?type=tcp&security=reality#%s", u.UUID, domain, port, u.Username)
	case "hysteria2":
		return fmt.Sprintf("hy2://%s@%s:%d#%s", u.Password, domain, port, u.Username)
	case "tuic":
		return fmt.Sprintf("tuic://%s:%s@%s:%d#%s", u.UUID, u.Password, domain, port, u.Username)
	default:
		return ""
	}
}

func reloadSingbox() {
	// Gọi file main.sh của bạn để build lại config và restart
	cmd := exec.Command("bash", "-c", "/opt/menu-singbox-vvc/main.sh rebuild_config && systemctl restart sing-box")
	if err := cmd.Run(); err != nil {
		log.Printf("Lỗi khi tải lại sing-box: %v", err)
	} else {
		log.Println("Sing-box đã nhận cấu hình mới thành công.")
	}
}

func generateUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func generateRandomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "P@ssw0rdError"
	}
	for i, x := range b {
		b[i] = letters[x%byte(len(letters))]
	}
	return string(b)
}
