package handlers

import (
	"context"
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
//	{"type":"input_audio","codec":"opus","data":"base64...","seq":1,"is_final":true}
//	{"type":"abort"}
//	{"type":"ping"}
type wsInboundFrame struct {
	Type    string `json:"type"`
	Text    string `json:"text,omitempty"`
	Codec   string `json:"codec,omitempty"`    // for input_audio: opus, pcm, wav
	Data    string `json:"data,omitempty"`     // for input_audio: base64 encoded audio
	Seq     int    `json:"seq,omitempty"`      // audio frame sequence number
	IsFinal bool   `json:"is_final,omitempty"` // true = last audio chunk (PTT release)
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
		return nil
	}
	defer conn.Close()

	sessionID := uuid.New().String()
	session := &companionadapter.Session{
		ID:           sessionID,
		BotID:        botID,
		UserID:       userID,
		Conn:         conn,
		LastActiveAt: time.Now(),
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

	conn.SetReadLimit(512 * 1024)
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	// reqCtx is the per-request context. It is cancelled when an "abort" frame
	// arrives so that in-flight HandleInbound calls are terminated cleanly.
	var (
		reqCtx    context.Context
		reqCancel context.CancelFunc
	)
	newReqCtx := func() context.Context {
		if reqCancel != nil {
			reqCancel()
		}
		reqCtx, reqCancel = context.WithCancel(c.Request().Context())
		session.CancelFn = reqCancel
		return reqCtx
	}
	defer func() {
		if reqCancel != nil {
			reqCancel()
		}
	}()

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
			session.UserText = text
			session.Touch()
			ctx := newReqCtx()
			receivedAt := time.Now().UTC()
			msg := h.buildInboundMsg(botID, userID, sessionID, text, receivedAt)
			go func() {
				if err := h.channelManager.HandleInbound(ctx, cfg, msg); err != nil {
					if ctx.Err() != nil {
						return // aborted — suppress error
					}
					h.log.Error("HandleInbound error", slog.String("error", err.Error()))
					_ = session.WriteJSON(map[string]string{
						"type":    "error",
						"message": "internal error",
					})
				}
			}()

		case "input_audio":
			audioData, err := base64.StdEncoding.DecodeString(frame.Data)
			if err != nil || len(audioData) == 0 {
				if err != nil {
					h.log.Warn("invalid audio data", slog.String("error", err.Error()))
				}
				_ = session.WriteJSON(map[string]string{"type": "error", "message": "invalid audio data"})
				continue
			}

			if h.sttService == nil {
				_ = session.WriteJSON(map[string]string{"type": "error", "message": "语音识别服务未配置"})
				continue
			}

			session.Touch()
			ctx := newReqCtx()
			codec := frame.Codec

			go func() {
				h.log.Debug("transcribing audio", slog.Int("bytes", len(audioData)), slog.String("codec", codec))
				text, err := h.sttService.Transcribe(ctx, audioData, codec)
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					h.log.Error("stt failed", slog.String("error", err.Error()))
					_ = session.WriteJSON(map[string]string{"type": "error", "message": "语音识别失败"})
					return
				}
				text = strings.TrimSpace(text)
				if text == "" {
					_ = session.WriteJSON(map[string]string{"type": "error", "message": "未能识别语音内容"})
					return
				}
				h.log.Info("stt result", slog.String("text", text))
				// Echo transcription back to the client.
				_ = session.WriteJSON(map[string]string{"type": "transcription", "text": text})

				session.UserText = text
				receivedAt := time.Now().UTC()
				msg := h.buildInboundMsg(botID, userID, sessionID, text, receivedAt)
				if err := h.channelManager.HandleInbound(ctx, cfg, msg); err != nil {
					if ctx.Err() != nil {
						return
					}
					h.log.Error("HandleInbound error (audio)", slog.String("error", err.Error()))
					_ = session.WriteJSON(map[string]string{"type": "error", "message": "internal error"})
				}
			}()

		case "abort":
			// Cancel the currently in-flight request.
			session.Cancel()
			h.log.Debug("abort received", slog.String("session_id", sessionID))

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

// buildInboundMsg constructs a channel.InboundMessage for HandleInbound.
func (h *CompanionHandler) buildInboundMsg(botID, userID, sessionID, text string, receivedAt time.Time) channel.InboundMessage {
	return channel.InboundMessage{
		Channel: companionadapter.CompanionType,
		Message: channel.Message{
			Parts: []channel.MessagePart{{Type: channel.MessagePartText, Text: text}},
		},
		BotID:       botID,
		ReplyTarget: sessionID,
		RouteKey:    sessionID,
		Sender: channel.Identity{
			SubjectID: userID,
			Attributes: map[string]string{"user_id": userID},
		},
		Conversation: channel.Conversation{
			ID:   botID + ":" + userID,
			Type: "p2p",
		},
		ReceivedAt: receivedAt,
		Source:     "companion",
	}
}
