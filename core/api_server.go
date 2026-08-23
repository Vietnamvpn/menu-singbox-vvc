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
	nodesFile     = filepath.Join(DataDir, "nodes.json")
	entryNodeFile = filepath.Join(DataDir, "entry-node.json")
	apiConfigFile = filepath.Join(DataDir, "api_config.json")
	fileMutex     sync.Mutex
)

type ApiConfig struct {
	URL   string `json:"url"`
	Token string `json:"token"`
	Port  int    `json:"port"`
}

// Cấu trúc User chuẩn khớp với users.json trên VPS
type User struct {
	Username string `json:"username"`
	Tag      string `json:"tag"`
	Secret   string `json:"secret"`
}

type ResetRequest struct {
	Username string `json:"username"`
}

type ResetResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	NewLink string `json:"new_link,omitempty"`
}

type Task struct {
	ID      int    `json:"id"`
	Action  string `json:"action"`
	Payload string `json:"payload"`
}

type TasksResponse struct {
	Status string `json:"status"`
	Tasks  []Task `json:"tasks"`
}

type EntryNode struct {
	Tag    string `json:"tag"`
	Domain string `json:"domain"`
	Port   int    `json:"port"`
}

func main() {
	os.MkdirAll(DataDir, 0755)

	// Tiến trình đồng bộ định kỳ (1 phút/lần)
	go systemSyncRoutine()

	// HTTP API Endpoint chờ lệnh reset password
	http.HandleFunc("/api/reset-password", handleResetPassword)

	log.Printf("Sing-box Manager API Server đang chạy tại port %s", ListenAddr)
	if err := http.ListenAndServe(ListenAddr, nil); err != nil {
		log.Fatalf("Lỗi khởi động API server: %v", err)
	}
}

func getApiConfig() (string, string, int) {
	data, err := os.ReadFile(apiConfigFile)
	if err != nil {
		return "", "", 0
	}
	var config ApiConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return "", "", 0
	}
	return config.URL, config.Token, config.Port
}

func sendApiRequest(action string, payload map[string]interface{}, result interface{}) error {
	baseURL, token, port := getApiConfig()
	if baseURL == "" || token == "" {
		return fmt.Errorf("chưa cấu hình API URL hoặc Token")
	}

	payload["action"] = action
	jsonBody, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("POST", baseURL, bytes.NewBuffer(jsonBody))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Port", fmt.Sprintf("%d", port))
	req.Header.Set("X-API-Token", token)

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("API trả về mã lỗi HTTP: %d", resp.StatusCode)
	}

	if result != nil {
		return json.NewDecoder(resp.Body).Decode(result)
	}
	return nil
}

func handleResetPassword(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	_, serverToken, _ := getApiConfig()
	clientToken := r.Header.Get("Authorization")
	if serverToken != "" && clientToken != "Bearer "+serverToken && r.Header.Get("X-API-Token") != serverToken {
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
			users[i].Secret = generateUUID()
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

func systemSyncRoutine() {
	ticker := time.NewTicker(1 * time.Minute)
	for range ticker.C {
		baseURL, token, _ := getApiConfig()
		if baseURL == "" || token == "" {
			continue
		}

		func() {
			var inbounds []map[string]interface{}
			if data, err := os.ReadFile(nodesFile); err == nil {
				json.Unmarshal(data, &inbounds)
			}
			if len(inbounds) > 0 {
				var res map[string]interface{}
				_ = sendApiRequest("report_inbounds", map[string]interface{}{
					"inbounds": inbounds,
				}, &res)
			}
		}()

		func() {
			var taskResp TasksResponse
			err := sendApiRequest("get_tasks", map[string]interface{}{}, &taskResp)
			if err == nil && len(taskResp.Tasks) > 0 {
				for _, task := range taskResp.Tasks {
					executeTask(task)
				}
			}
		}()

		func() {
			logs := []map[string]interface{}{}
			_ = sendApiRequest("report_traffic", map[string]interface{}{
				"logs": logs,
			}, nil)
		}()
	}
}

func executeTask(task Task) {
	fileMutex.Lock()
	defer fileMutex.Unlock()

	debugFile := filepath.Join(DataDir, "debug_task.json")
	if debugData, err := json.MarshalIndent(task, "", "  "); err == nil {
		_ = os.WriteFile(debugFile, debugData, 0644)
	}

	var payload map[string]interface{}
	if task.Payload != "" {
		_ = json.Unmarshal([]byte(task.Payload), &payload)
	}

	actionType := payload["action"]
	if actionType == nil {
		actionType = task.Action
	}

	var taskStatus = "done"
	var errorMsg *string

	switch actionType {
	case "add_user", "create_user":
		username, _ := payload["username"].(string)

		// Lấy giá trị secret/uuid từ payload web gửi xuống
		var secret string
		if s, ok := payload["secret"].(string); ok && s != "" {
			secret = s
		} else if u, ok := payload["uuid"].(string); ok && u != "" {
			secret = u
		} else if p, ok := payload["password"].(string); ok && p != "" {
			secret = p
		} else {
			secret = generateUUID()
		}

		if username != "" {
			users, err := readUsers()
			if err != nil {
				users = []User{}
			}

			exists := false
			for i, u := range users {
				if u.Username == username {
					users[i].Secret = secret
					if users[i].Tag == "" {
						users[i].Tag = "all"
					}
					exists = true
					break
				}
			}

			if !exists {
				tag := "all"
				if t, ok := payload["tag"].(string); ok && t != "" {
					tag = t
				}
				users = append(users, User{
					Username: username,
					Tag:      tag,
					Secret:   secret,
				})
			}

			if err := writeUsers(users); err == nil {
				log.Printf("[TASK] Đã thêm/cập nhật user từ web: %s", username)
				go reloadSingbox() // Gọi build_and_apply_config trong utils.sh
			} else {
				errMsg := err.Error()
				errorMsg = &errMsg
				taskStatus = "error"
			}
		} else {
			errMsg := "Username trống trong payload"
			errorMsg = &errMsg
			taskStatus = "error"
		}

	case "delete_user", "remove_user":
		username, _ := payload["username"].(string)
		if username != "" {
			users, err := readUsers()
			if err == nil {
				var newUsers []User
				found := false
				for _, u := range users {
					if u.Username != username {
						newUsers = append(newUsers, u)
					} else {
						found = true
					}
				}
				if found {
					if err := writeUsers(newUsers); err == nil {
						log.Printf("[TASK] Đã xóa user từ web: %s", username)
						go reloadSingbox()
					} else {
						errMsg := err.Error()
						errorMsg = &errMsg
						taskStatus = "error"
					}
				}
			}
		}

	default:
		log.Printf("[TASK] Hành động không hỗ trợ: %v", actionType)
	}

	_ = sendApiRequest("update_task_status", map[string]interface{}{
		"task_id":     task.ID,
		"task_status": taskStatus,
		"error_msg":   errorMsg,
	}, nil)
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

func getEntryNodeInfo(tag string) (string, int) {
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
	return "VPS_IP_OR_DOMAIN", 443
}

func generateProxyLink(u User) string {
	domain, port := getEntryNodeInfo(u.Tag)
	return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=tcp&security=reality&sni=%s#%s",
		u.Secret, domain, port, domain, u.Username)
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
