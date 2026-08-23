package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

const (
	ListenAddr = ":8080"
	DataDir    = "/opt/menu-singbox-vvc/data"
)

var (
	usersFile     = filepath.Join(DataDir, "users.json")
	entryNodeFile = filepath.Join(DataDir, "entry-node.json")
	apiConfigFile = filepath.Join(DataDir, "api_config.json")
	fileMutex     sync.Mutex
)

// Cấu hình API Web trung tâm đọc từ tệp do api-web.sh quản lý
type ApiConfig struct {
	URL   string `json:"url"`
	Token string `json:"token"`
}

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

// Cấu trúc Lệnh đồng bộ nhận từ Web trung tâm
type ServerCommand struct {
	Action string          `json:"action"` // add_user, delete_user, toggle_service...
	Params json.RawMessage `json:"params"`
}

type SyncResponse struct {
	Status   string          `json:"status"`
	Commands []ServerCommand `json:"commands"`
}

// Cấu trúc Entry Node để thay thế IP/Port trước khi trả link
type EntryNode struct {
	Tag    string `json:"tag"`
	Domain string `json:"domain"`
	Port   int    `json:"port"`
}

func main() {
	os.MkdirAll(DataDir, 0755)

	// Chạy tiến trình đồng bộ tổng hợp (Vừa đẩy traffic, vừa nhận lệnh mỗi 1 phút)
	go systemSyncRoutine()

	// Mở HTTP API Server chờ lệnh tức thời từ Web trung tâm (ví dụ: Reset Token)
	http.HandleFunc("/api/reset-password", handleResetPassword)

	log.Printf("Sing-box Manager API Server đang chạy tại port %s", ListenAddr)
	if err := http.ListenAndServe(ListenAddr, nil); err != nil {
		log.Fatalf("Lỗi khởi động API server: %v", err)
	}
}

// Đọc cấu hình API động từ tệp cấu hình của hệ thống
func getApiConfig() (string, string) {
	data, err := os.ReadFile(apiConfigFile)
	if err != nil {
		return "", ""
	}
	var config ApiConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return "", ""
	}
	return config.URL, config.Token
}

// Xử lý yêu cầu reset từ web trung tâm (Có kiểm tra Token xác thực)
func handleResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	// Xác thực Token từ Header (Bearer Token)
	_, serverToken := getApiConfig()
	clientToken := r.Header.Get("Authorization")
	if serverToken != "" && clientToken != "Bearer "+serverToken {
		sendJSONResponse(w, "error", "Unauthorized: Token không hợp lệ", "")
		return
	}

	var req ResetRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSONResponse(w, "error", "Payload không hợp lệ", "")
		return
	}

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

	if err := writeUsers(users); err != nil {
		sendJSONResponse(w, "error", "Lỗi ghi dữ liệu mới", "")
		return
	}

	newLink := generateProxyLink(*foundUser)
	go reloadSingbox()

	sendJSONResponse(w, "success", "Reset thành công", newLink)
}

// TIẾN TRÌNH ĐỒNG BỔ TỔNG HỢP (CHẠY MỖI 1 PHÚT)
func systemSyncRoutine() {
	ticker := time.NewTicker(1 * time.Minute)
	for range ticker.C {
		baseURL, token := getApiConfig()
		if baseURL == "" || token == "" {
			continue
		}

		client := &http.Client{Timeout: 15 * time.Second}

		// --- 1. Đẩy dữ liệu Traffic lên web kèm Token ---
		func() {
			payload := map[string]interface{}{
				"timestamp": time.Now().Unix(),
			}
			jsonBody, _ := json.Marshal(payload)

			req, err := http.NewRequest("POST", baseURL+"/push-traffic", bytes.NewBuffer(jsonBody))
			if err != nil {
				return
			}
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", "application/json")

			resp, err := client.Do(req)
			if err != nil {
				return
			}
			defer resp.Body.Close()
		}()

		// --- 2. Kiểm tra và nhận danh sách lệnh mới từ web kèm Token ---
		func() {
			req, err := http.NewRequest("GET", baseURL+"/sync-commands", nil)
			if err != nil {
				return
			}
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", "application/json")

			resp, err := client.Do(req)
			if err != nil {
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode == http.StatusOK {
				var syncResp SyncResponse
				if json.NewDecoder(resp.Body).Decode(&syncResp) == nil {
					for _, cmd := range syncResp.Commands {
						executeCommand(cmd)
					}
				}
			}
		}()
	}
}

// Thực thi các lệnh nhận từ web (Thêm user, Xóa user, Tắt/Bật mạng...)
func executeCommand(cmd ServerCommand) {
	fileMutex.Lock()
	defer fileMutex.Unlock()

	switch cmd.Action {
	case "add_user":
		var newUser User
		if json.Unmarshal(cmd.Params, &newUser) == nil {
			users, _ := readUsers()
			users = append(users, newUser)
			writeUsers(users)
			go reloadSingbox()
			log.Printf("[SYNC] Đã thêm user mới từ web: %s", newUser.Username)
		}
	case "delete_user":
		var params struct {
			Username string `json:"username"`
		}
		if json.Unmarshal(cmd.Params, &params) == nil {
			users, _ := readUsers()
			var filtered []User
			for _, u := range users {
				if u.Username != params.Username {
					filtered = append(filtered, u)
				}
			}
			writeUsers(filtered)
			go reloadSingbox()
			log.Printf("[SYNC] Đã xóa user từ web: %s", params.Username)
		}
	case "toggle_service":
		var params struct {
			State string `json:"state"` // "start" hoặc "stop"
		}
		if json.Unmarshal(cmd.Params, &params) == nil {
			if params.State == "stop" {
				exec.Command("systemctl", "stop", "sing-box").Run()
				log.Println("[SYNC] Nhận lệnh từ web: Đã tắt mạng (dừng sing-box).")
			} else if params.State == "start" {
				exec.Command("systemctl", "start", "sing-box").Run()
				log.Println("[SYNC] Nhận lệnh từ web: Đã bật mạng (khởi động sing-box).")
			}
		}
	}
}

func sendJSONResponse(w http.ResponseWriter, status, message, link string) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ResetResponse{
		Status:  status,
		Message: message,
		NewLink: link,
	})
}

func readUsers() ([]User, error) {
	data, err := os.ReadFile(usersFile)
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
	return os.WriteFile(usersFile, data, 0644)
}

func getEntryNodeInfo(tag string, defaultPort int) (string, int) {
	data, err := os.ReadFile(entryNodeFile)
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
	return "VPS_IP_OR_DOMAIN", defaultPort
}

func generateProxyLink(u User) string {
	domain, port := getEntryNodeInfo(u.Tag, u.Port)

	switch u.Protocol {
	case "vless", "vless-reality":
		// Chuẩn VLESS TCP Reality
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=tcp&security=reality&sni=%s#%s",
			u.UUID, domain, port, domain, u.Username)

	case "vless-grpc":
		// Chuẩn VLESS gRPC Reality
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=grpc&security=reality&serviceName=grpc&sni=%s#%s",
			u.UUID, domain, port, domain, u.Username)

	case "vless-ws":
		// Chuẩn VLESS WebSocket TLS
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=ws&security=tls&path=/vless&sni=%s#%s",
			u.UUID, domain, port, domain, u.Username)

	case "hysteria2", "hy2":
		// Chuẩn Hysteria2
		return fmt.Sprintf("hy2://%s@%s:%d?sni=%s&insecure=1#%s",
			u.Password, domain, port, domain, u.Username)

	case "tuic":
		// Chuẩn TUIC
		return fmt.Sprintf("tuic://%s:%s@%s:%d?sni=%s&congestion_control=bbr#%s",
			u.UUID, u.Password, domain, port, domain, u.Username)

	default:
		return ""
	}
}

func reloadSingbox() {
	cmd := exec.Command("bash", "-c", "source /opt/menu-singbox-vvc/modules/utils.sh && build_and_apply_config")
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
