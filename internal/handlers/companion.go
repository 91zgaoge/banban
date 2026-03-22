package handlers

import (
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/labstack/echo/v4"

	"github.com/Kxiandaoyan/Memoh-v2/internal/accounts"
	"github.com/Kxiandaoyan/Memoh-v2/internal/bots"
	"github.com/Kxiandaoyan/Memoh-v2/internal/channel"
	companionadapter "github.com/Kxiandaoyan/Memoh-v2/internal/channel/adapters/companion"
	"github.com/Kxiandaoyan/Memoh-v2/internal/stt"
)

var companionUpgrader = websocket.Upgrader{
	HandshakeTimeout: 10 * time.Second,
	ReadBufferSize:   4096,
	WriteBufferSize:  4096,
	CheckOrigin:      func(r *http.Request) bool { return true },
}

// wsInboundFrame is the JSON frame received from the Flutter client.
//
//	{"type":"input_text","text":"今天好累"}
//	{"type":"input_audio","codec":"opus","data":"base64..."}
//	{"type":"abort"}
//	{"type":"ping"}
type wsInboundFrame struct {
	Type   string `json:"type"`
	Text   string `json:"text,omitempty"`
	Codec  string `json:"codec,omitempty"`  // for input_audio: opus, pcm, wav
	Data   string `json:"data,omitempty"`   // for input_audio: base64 encoded audio
}

// CompanionHandler handles the companion WebSocket endpoint.
type CompanionHandler struct {
	log            *slog.Logger
	hub            *companionadapter.SessionHub
	channelManager *channel.Manager
	channelService *channel.Service
	botService     *bots.Service
	accountService *accounts.Service
	sttService     stt.Service
}

// NewCompanionHandler creates a CompanionHandler.
func NewCompanionHandler(
	log *slog.Logger,
	hub *companionadapter.SessionHub,
	channelManager *channel.Manager,
	channelService *channel.Service,
	botService *bots.Service,
	accountService *accounts.Service,
	sttService stt.Service,
) *CompanionHandler {
	return &CompanionHandler{
		log:            log.With(slog.String("handler", "companion")),
		hub:            hub,
		channelManager: channelManager,
		channelService: channelService,
		botService:     botService,
		accountService: accountService,
		sttService:     sttService,
	}
}

// Register registers companion routes.
func (h *CompanionHandler) Register(e *echo.Echo) {
	e.GET("/bots/:bot_id/companion/ws", h.HandleWS)
}

// HandleWS upgrades the HTTP connection to WebSocket, registers the session,
// and processes inbound frames until the connection closes.
func (h *CompanionHandler) HandleWS(c echo.Context) error {
	// Auth is handled by the JWT middleware (query:token or Bearer header).
	userID, err := RequireChannelIdentityID(c)
	if err != nil {
		return err
	}

	botID := strings.TrimSpace(c.Param("bot_id"))
	if botID == "" {
		return echo.NewHTTPError(http.StatusBadRequest, "bot id is required")
	}

	if _, err := AuthorizeBotAccess(c.Request().Context(), h.botService, h.accountService, userID, botID,
		bots.AccessPolicy{AllowPublicMember: true}); err != nil {
		return err
	}

	conn, err := companionUpgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		h.log.Error("ws upgrade failed", slog.String("error", err.Error()))
		return nil // upgrader already wrote error response
	}
	defer conn.Close()

	sessionID := uuid.New().String()
	session := &companionadapter.Session{
		ID:     sessionID,
		BotID:  botID,
		UserID: userID,
		Conn:   conn,
	}
	h.hub.Register(session)
	defer h.hub.Unregister(sessionID)

	h.log.Info("companion session opened",
		slog.String("session_id", sessionID),
		slog.String("bot_id", botID),
		slog.String("user_id", userID),
	)

	cfg, err := h.channelService.ResolveEffectiveConfig(c.Request().Context(), botID, companionadapter.CompanionType)
	if err != nil {
		h.log.Error("failed to resolve channel config", slog.String("error", err.Error()))
		cfg = channel.ChannelConfig{}
	}

	conn.SetReadLimit(512 * 1024) // 512 KB max frame
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		msgType, raw, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				h.log.Warn("ws read error", slog.String("error", err.Error()))
			}
			break
		}
		if msgType != websocket.TextMessage {
			continue
		}

		var frame wsInboundFrame
		if err := json.Unmarshal(raw, &frame); err != nil {
			h.log.Warn("invalid ws frame", slog.String("error", err.Error()))
			continue
		}

		switch frame.Type {
		case "ping":
			_ = session.WriteJSON(map[string]string{"type": "pong"})

		case "input_text":
			text := strings.TrimSpace(frame.Text)
			if text == "" {
				continue
			}
			// Store user text on the session so the outbound stream can pass it
			// to the memory indexer after StreamEventFinal fires.
			session.UserText = text
			receivedAt := time.Now().UTC()
			msg := channel.InboundMessage{
				Channel: companionadapter.CompanionType,
				Message: channel.Message{
					Parts: []channel.MessagePart{{Type: channel.MessagePartText, Text: text}},
				},
				BotID:       botID,
				ReplyTarget: sessionID,
				RouteKey:    sessionID,
				Sender: channel.Identity{
					SubjectID: userID,
					Attributes: map[string]string{
						"user_id": userID,
					},
				},
				Conversation: channel.Conversation{
					ID:   botID + ":" + userID,
					Type: "p2p",
				},
				ReceivedAt: receivedAt,
				Source:     "companion",
			}
			ctx := c.Request().Context()
			if err := h.channelManager.HandleInbound(ctx, cfg, msg); err != nil {
				h.log.Error("HandleInbound error", slog.String("error", err.Error()))
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "internal error",
				})
			}

		case "input_audio":
			// Decode base64 audio data
			audioData, err := base64.StdEncoding.DecodeString(frame.Data)
			if err != nil {
				h.log.Warn("invalid audio data", slog.String("error", err.Error()))
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "invalid audio data",
				})
				continue
			}
			if len(audioData) == 0 {
				continue
			}

			// Use STT service to transcribe audio
			if h.sttService == nil {
				h.log.Warn("stt service not configured")
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "语音识别服务未配置",
				})
				continue
			}

			h.log.Debug("transcribing audio", slog.Int("bytes", len(audioData)), slog.String("codec", frame.Codec))
			ctx := c.Request().Context()
			text, err := h.sttService.Transcribe(ctx, audioData, frame.Codec)
			if err != nil {
				h.log.Error("stt failed", slog.String("error", err.Error()))
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "语音识别失败",
				})
				continue
			}

			text = strings.TrimSpace(text)
			if text == "" {
				h.log.Debug("stt returned empty text")
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "未能识别语音内容",
				})
				continue
			}

			h.log.Info("stt result", slog.String("text", text))

			// Send transcription back to client as a status message
			_ = session.WriteJSON(map[string]string{
				"type": "transcription",
				"text": text,
			})

			// Store user text on the session and process as input_text
			session.UserText = text
			receivedAt := time.Now().UTC()
			msg := channel.InboundMessage{
				Channel: companionadapter.CompanionType,
				Message: channel.Message{
					Parts: []channel.MessagePart{{Type: channel.MessagePartText, Text: text}},
				},
				BotID:       botID,
				ReplyTarget: sessionID,
				RouteKey:    sessionID,
				Sender: channel.Identity{
					SubjectID: userID,
					Attributes: map[string]string{
						"user_id": userID,
					},
				},
				Conversation: channel.Conversation{
					ID:   botID + ":" + userID,
					Type: "p2p",
				},
				ReceivedAt: receivedAt,
				Source:     "companion",
			}
			if err := h.channelManager.HandleInbound(ctx, cfg, msg); err != nil {
				h.log.Error("HandleInbound error", slog.String("error", err.Error()))
				_ = session.WriteJSON(map[string]string{
					"type":    "error",
					"message": "internal error",
				})
			}

		case "abort":
			// Future: cancel in-flight generation.

		default:
			h.log.Debug("unknown ws frame type", slog.String("type", frame.Type))
		}
	}

	h.log.Info("companion session closed",
		slog.String("session_id", sessionID),
		slog.String("bot_id", botID),
	)
	return nil
}
