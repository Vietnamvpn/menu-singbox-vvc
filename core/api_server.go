package main

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	ListenAddr = ":8080"
	DataDir    = "/opt/menu-singbox-vvc/data"
	LogDir     = "/opt/menu-singbox-vvc/logs"
)

var (
	usersFile     = filepath.Join(DataDir, "users.json")
	nodesFile     = filepath.Join(DataDir, "nodes.json")
	entryNodeFile = filepath.Join(DataDir, "entry-node.json")
	apiConfigFile = filepath.Join(DataDir, "api_config.json")
	fileMutex     sync.Mutex
	reloadMutex   sync.Mutex
)

type ApiConfig struct {
	URL   string `json:"url"`
	Token string `json:"token"`
	Port  int    `json:"port"`
}

type User struct {
	Username string `json:"username"`
	Tag      string `json:"tag"`
	UUID     string `json:"uuid"`
	Status   string `json:"status,omitempty"`
}

type Node struct {
	Type        string `json:"type"`
	Tag         string `json:"tag"`
	Domain      string `json:"domain"`
	Address     string `json:"address"`
	Port        int    `json:"port"`
	SNI         string `json:"sni"`
	PublicKey   string `json:"public_key"`
	ShortID     string `json:"short_id"`
	WSPath      string `json:"ws_path"`
	GRPCService string `json:"grpc_service"`
	Password    string `json:"password"`
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
	ID      interface{}     `json:"id"`
	Action  string          `json:"action"`
	Payload json.RawMessage `json:"payload"`
}

type TasksResponse struct {
	Status string `json:"status"`
	Tasks  []Task `json:"tasks"`
}

type EntryNode struct {
	NodeTag string `json:"node_tag"`
	Address string `json:"address"`
	Port    int    `json:"port"`
}

type SingboxStat struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

type SingboxStatsResponse struct {
	Stat  []SingboxStat `json:"stat"`
	Stats []SingboxStat `json:"stats"`
}

func main() {
	os.MkdirAll(DataDir, 0755)
	os.MkdirAll(LogDir, 0755)

	// Cấu hình ghi log ra đồng thời màn hình console và file server.log
	logFile, err := os.OpenFile(filepath.Join(LogDir, "server.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err == nil {
		log.SetOutput(io.MultiWriter(os.Stdout, logFile))
	} else {
		log.Printf("Không thể mở file log hệ thống: %v", err)
	}

	go systemSyncRoutine()

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

	log.Printf("[API GỬI ĐI] Action: %s | Payload: %s", action, string(jsonBody))

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
	users, err := readUsers()
	if err != nil {
		fileMutex.Unlock()
		sendJSONResponse(w, "error", "Lỗi đọc dữ liệu users", "")
		return
	}

	var foundUser *User
	for i := range users {
		if users[i].Username == req.Username {
			users[i].UUID = generateUUID()
			foundUser = &users[i]
			break
		}
	}

	if foundUser == nil {
		fileMutex.Unlock()
		sendJSONResponse(w, "error", "Không tìm thấy User", "")
		return
	}

	if err := writeUsers(users); err != nil {
		fileMutex.Unlock()
		sendJSONResponse(w, "error", "Lỗi ghi dữ liệu mới", "")
		return
	}
	fileMutex.Unlock()

	newLink := generateProxyLink(*foundUser)
	log.Printf("[RESET LINK] User: %s | Link mới được cấp: %s", foundUser.Username, newLink)

	go reloadSingbox()

	sendJSONResponse(w, "success", "Reset thành công", newLink)
}

func systemSyncRoutine() {
	if _, err := exec.LookPath("grpcurl"); err != nil {
		_ = exec.Command("apt-get", "update", "-y").Run()
		_ = exec.Command("apt-get", "install", "-y", "grpcurl").Run()
	}

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
				needReload := false
				for _, task := range taskResp.Tasks {
					changed := executeTask(task)
					if changed {
						needReload = true
					}
				}
				if needReload {
					go reloadSingbox()
				}
			}
		}()

		func() {
			logs := []map[string]interface{}{}

			cmd := exec.Command("grpcurl", "-plaintext", "-d", `{"pattern": "", "reset": false}`, "127.0.0.1:10085", "v2ray.core.app.stats.command.StatsService/QueryStats")
			output, err := cmd.Output()
			if err == nil && len(output) > 0 {
				var statsResp SingboxStatsResponse
				if err := json.Unmarshal(output, &statsResp); err == nil {
					statsList := statsResp.Stat
					if len(statsList) == 0 {
						statsList = statsResp.Stats
					}

					userTraffic := make(map[string]map[string]int64)
					for _, s := range statsList {
						parts := strings.Split(s.Name, ">>>")
						if len(parts) >= 4 && parts[0] == "user" && parts[2] == "traffic" {
							username := parts[1]
							trafficType := parts[3]

							if _, exists := userTraffic[username]; !exists {
								userTraffic[username] = map[string]int64{"upload": 0, "download": 0}
							}

							if trafficType == "uplink" || trafficType == "up" {
								userTraffic[username]["upload"] += s.Value
							} else if trafficType == "downlink" || trafficType == "down" {
								userTraffic[username]["download"] += s.Value
							}
						}
					}

					for u, t := range userTraffic {
						logs = append(logs, map[string]interface{}{
							"username": u,
							"upload":   t["upload"],
							"download": t["download"],
						})
					}

					if len(logs) > 0 {
						trafficReportFile := filepath.Join(LogDir, "traffic_report.json")
						if reportData, err := json.MarshalIndent(logs, "", "  "); err == nil {
							_ = os.WriteFile(trafficReportFile, reportData, 0644)
						}

						log.Printf("[TRAFFIC REPORT] Đang gửi dữ liệu sử dụng của %d user lên web", len(logs))
						_ = sendApiRequest("report_traffic", map[string]interface{}{
							"logs": logs,
						}, nil)
					}
				}
			}
		}()
	}
}

func executeTask(task Task) bool {
	fileMutex.Lock()
	defer fileMutex.Unlock()

	debugFile := filepath.Join(LogDir, "debug_task.json")
	if debugData, err := json.MarshalIndent(task, "", "  "); err == nil {
		_ = os.WriteFile(debugFile, debugData, 0644)
	}

	log.Printf("[API NHẬN VỀ] Task ID: %v | Action: %s | Payload: %s", task.ID, task.Action, string(task.Payload))

	var payload map[string]interface{}
	if len(task.Payload) > 0 {
		if err := json.Unmarshal(task.Payload, &payload); err != nil {
			var payloadStr string
			if errStr := json.Unmarshal(task.Payload, &payloadStr); errStr == nil {
				_ = json.Unmarshal([]byte(payloadStr), &payload)
			}
		}
	}

	actionType := payload["action"]
	if actionType == nil {
		actionType = task.Action
	}

	var taskStatus = "done"
	var errorMsg *string
	needReload := false

	switch actionType {
	case "add_user", "create_user", "reset_token":
		username, _ := payload["username"].(string)
		uuid, _ := payload["uuid"].(string)
		status, _ := payload["status"].(string)

		if username != "" && uuid != "" {
			users, err := readUsers()
			if err != nil {
				users = []User{}
			}
			exists := false
			for i, u := range users {
				if u.Username == username {
					users[i].UUID = uuid
					if status != "" {
						users[i].Status = status
					}
					if users[i].Tag == "" {
						users[i].Tag = "all"
					}
					exists = true
					break
				}
			}
			if !exists {
				if status == "" {
					status = "active"
				}
				users = append(users, User{
					Username: username,
					Tag:      "all",
					UUID:     uuid,
					Status:   status,
				})
			}
			if err := writeUsers(users); err == nil {
				log.Printf("[TASK] Đã thêm/cập nhật user từ web: %s (Status: %s)", username, status)
				needReload = true
			} else {
				errMsg := err.Error()
				errorMsg = &errMsg
				taskStatus = "error"
			}
		} else {
			errMsg := "Username hoặc UUID trống trong payload"
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
						needReload = true
					} else {
						errMsg := err.Error()
						errorMsg = &errMsg
						taskStatus = "error"
					}
				}
			}
		}

	case "toggle_user":
		username, _ := payload["username"].(string)
		status, _ := payload["status"].(string)

		log.Printf("[TASK] Nhận lệnh toggle_user cho %s với trạng thái %s", username, status)
		users, err := readUsers()
		if err == nil {
			updated := false
			for i := range users {
				if users[i].Username == username {
					users[i].Status = status
					updated = true
					break
				}
			}
			if updated {
				if err := writeUsers(users); err == nil {
					needReload = true
				} else {
					errMsg := err.Error()
					errorMsg = &errMsg
					taskStatus = "error"
				}
			}
		}

	case "toggle_service":
		state, _ := payload["state"].(string)
		if state == "stop" {
			exec.Command("systemctl", "stop", "sing-box").Run()
			log.Println("[TASK] Đã tắt dịch vụ sing-box theo lệnh từ web.")
		} else if state == "start" {
			exec.Command("systemctl", "start", "sing-box").Run()
			log.Println("[TASK] Đã bật dịch vụ sing-box theo lệnh từ web.")
		}

	default:
		log.Printf("[TASK] Hành động không hỗ trợ: %v", actionType)
	}

	_ = sendApiRequest("update_task_status", map[string]interface{}{
		"task_id":     task.ID,
		"task_status": taskStatus,
		"error_msg":   errorMsg,
	}, nil)

	return needReload
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

func getMatchingEntryNodes(tag string) []EntryNode {
	var matched []EntryNode
	data, err := os.ReadFile(entryNodeFile)
	if err == nil {
		var entries []EntryNode
		if json.Unmarshal(data, &entries) == nil {
			for _, e := range entries {
				if e.NodeTag == tag {
					matched = append(matched, e)
				}
			}
		}
	}
	return matched
}

func buildLinkWithDetails(uuid, domain string, port int, n Node, tagLabel string) string {
	sni := n.SNI
	if sni == "" {
		sni = domain
	}

	switch n.Type {
	case "vless-reality":
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s",
			uuid, domain, port, sni, n.PublicKey, n.ShortID, tagLabel)

	case "vless-grpc-reality":
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=grpc&serviceName=%s#%s",
			uuid, domain, port, sni, n.PublicKey, n.ShortID, n.GRPCService, tagLabel)

	case "vless-ws-tls":
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&security=tls&sni=%s&type=ws&path=%s&allowInsecure=1#%s",
			uuid, domain, port, sni, n.WSPath, tagLabel)

	case "hysteria2":
		return fmt.Sprintf("hysteria2://%s@%s:%d?sni=%s&insecure=1#%s",
			uuid, domain, port, sni, tagLabel)

	case "tuic":
		return fmt.Sprintf("tuic://%s:%s@%s:%d?congestion_control=bbr&sni=%s&alpn=h3&insecure=1#%s",
			uuid, n.Password, domain, port, sni, tagLabel)

	default:
		return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=tcp&security=reality&sni=%s#%s",
			uuid, domain, port, sni, tagLabel)
	}
}

func generateLinksForNode(u User, n Node) []string {
	var links []string
	tagLabel := fmt.Sprintf("%s-%s", u.Username, n.Tag)
	entries := getMatchingEntryNodes(n.Tag)

	if len(entries) > 0 {
		for _, entry := range entries {
			domain := entry.Address
			port := entry.Port
			if domain != "" && port > 0 {
				links = append(links, buildLinkWithDetails(u.UUID, domain, port, n, tagLabel))
			}
		}
	} else {
		domain := n.Domain
		if domain == "" {
			domain = n.Address
		}
		if domain == "" {
			domain = "VPS_IP_OR_DOMAIN"
		}
		port := n.Port
		links = append(links, buildLinkWithDetails(u.UUID, domain, port, n, tagLabel))
	}

	return links
}

func generateProxyLink(u User) string {
	data, err := os.ReadFile(nodesFile)
	if err == nil {
		var nodes []Node
		if json.Unmarshal(data, &nodes) == nil && len(nodes) > 0 {
			var allLinks []string
			for _, n := range nodes {
				if u.Tag == "all" || u.Tag == "" || u.Tag == n.Tag {
					allLinks = append(allLinks, generateLinksForNode(u, n)...)
				}
			}
			if len(allLinks) > 0 {
				return strings.Join(allLinks, "\n")
			}
		}
	}

	entries := getMatchingEntryNodes(u.Tag)
	domain := "VPS_IP_OR_DOMAIN"
	port := 443
	if len(entries) > 0 {
		domain = entries[0].Address
		port = entries[0].Port
	}
	return fmt.Sprintf("vless://%s@%s:%d?encryption=none&type=tcp&security=reality&sni=%s#%s",
		u.UUID, domain, port, domain, u.Username)
}

func reloadSingbox() {
	reloadMutex.Lock()
	defer reloadMutex.Unlock()

	cmd := exec.Command("bash", "-c", "source /opt/menu-singbox-vvc/modules/utils.sh && build_and_apply_config /opt/menu-singbox-vvc/templates/config.base.json /etc/sing-box/config.json")
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
