package companion

import (
	"context"
	"fmt"
	"sync"
	"time"

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

	// CancelFn cancels the currently in-flight HandleInbound call.
	// Set by the handler before calling HandleInbound; called on "abort" frame.
	CancelFn context.CancelFunc

	// LastActiveAt is updated each time the user sends input_text or input_audio.
	LastActiveAt time.Time

	// ProactiveSentAt records the last time a proactive message was sent for
	// this session. Used to enforce a per-session cooldown period.
	ProactiveSentAt time.Time
}

// WriteJSON safely writes a JSON message to the WebSocket connection.
// gorilla/websocket requires only one concurrent writer per connection.
func (s *Session) WriteJSON(v any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.Conn.WriteJSON(v)
}

// Touch updates LastActiveAt to now. Call on every inbound user message.
func (s *Session) Touch() {
	s.mu.Lock()
	s.LastActiveAt = time.Now()
	s.mu.Unlock()
}

// ProactiveSentRecently reports whether a proactive message was sent within
// the last 2 hours for this session.
func (s *Session) ProactiveSentRecently() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return time.Since(s.ProactiveSentAt) < 2*time.Hour
}

// MarkProactiveSent records that a proactive message was just sent.
func (s *Session) MarkProactiveSent() {
	s.mu.Lock()
	s.ProactiveSentAt = time.Now()
	s.mu.Unlock()
}

// Cancel calls CancelFn if it is set, cancelling the in-flight request.
func (s *Session) Cancel() {
	s.mu.Lock()
	fn := s.CancelFn
	s.mu.Unlock()
	if fn != nil {
		fn()
	}
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

// All returns a snapshot of all active sessions.
func (h *SessionHub) All() []*Session {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]*Session, 0, len(h.sessions))
	for _, s := range h.sessions {
		out = append(out, s)
	}
	return out
}
