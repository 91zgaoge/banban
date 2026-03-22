package companion

import (
	"fmt"
	"sync"

	"github.com/gorilla/websocket"
)

// Session holds an active WebSocket connection and its associated metadata.
type Session struct {
	ID       string
	BotID    string
	UserID   string
	UserText string // last inbound user message, set before HandleInbound for memory indexing
	Conn     *websocket.Conn
	mu       sync.Mutex // protects concurrent writes to Conn
}

// WriteJSON safely writes a JSON message to the WebSocket connection.
// gorilla/websocket requires only one concurrent writer per connection.
func (s *Session) WriteJSON(v any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.Conn.WriteJSON(v)
}

// SessionHub manages active WebSocket sessions keyed by session ID.
//
// Each session is created when a WebSocket connection is established and
// removed when the connection closes. Session IDs are used as the routing
// target in channel.InboundMessage.ReplyTarget so the adapter can locate
// the correct connection when pushing stream events.
type SessionHub struct {
	mu       sync.RWMutex
	sessions map[string]*Session // key: sessionID
}

// NewSessionHub creates an empty SessionHub.
func NewSessionHub() *SessionHub {
	return &SessionHub{
		sessions: make(map[string]*Session),
	}
}

// Register stores a session in the hub.
func (h *SessionHub) Register(s *Session) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.sessions[s.ID] = s
}

// Unregister removes a session from the hub.
func (h *SessionHub) Unregister(sessionID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.sessions, sessionID)
}

// Get retrieves a session by ID. Returns an error if not found.
func (h *SessionHub) Get(sessionID string) (*Session, error) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	s, ok := h.sessions[sessionID]
	if !ok {
		return nil, fmt.Errorf("companion: session %q not found", sessionID)
	}
	return s, nil
}
