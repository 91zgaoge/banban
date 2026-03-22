package companion

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/Kxiandaoyan/Memoh-v2/internal/channel"
)

const (
	proactiveIdleThreshold = 30 * time.Minute
	proactiveScanInterval  = 5 * time.Minute
)

// ProactiveService scans active companion sessions and sends a warm greeting
// when a user has been idle for more than [proactiveIdleThreshold].
//
// Each session is only contacted once per 2-hour cooldown window
// (enforced by Session.ProactiveSentRecently / Session.MarkProactiveSent).
//
// Greeting flow:
//
//	  scan() → idle session found
//	      ↓
//	  build prompt + InboundMessage
//	      ↓
//	  channelMgr.HandleInbound → LLM → companion adapter → session.WriteJSON
//	      ↓
//	  session.MarkProactiveSent()
type ProactiveService struct {
	hub        *SessionHub
	channelMgr *channel.Manager
	channelSvc *channel.Service
	log        *slog.Logger
}

// NewProactiveService creates a ProactiveService.
func NewProactiveService(
	log *slog.Logger,
	hub *SessionHub,
	channelMgr *channel.Manager,
	channelSvc *channel.Service,
) *ProactiveService {
	return &ProactiveService{
		hub:        hub,
		channelMgr: channelMgr,
		channelSvc: channelSvc,
		log:        log.With(slog.String("component", "proactive")),
	}
}

// Run starts the background scan loop. It blocks until ctx is cancelled.
func (p *ProactiveService) Run(ctx context.Context) {
	ticker := time.NewTicker(proactiveScanInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			p.scan(ctx)
		case <-ctx.Done():
			return
		}
	}
}

func (p *ProactiveService) scan(ctx context.Context) {
	sessions := p.hub.All()
	for _, s := range sessions {
		idle := time.Since(s.LastActiveAt)
		if idle >= proactiveIdleThreshold && !s.ProactiveSentRecently() {
			go p.send(ctx, s)
		}
	}
}

func (p *ProactiveService) send(ctx context.Context, s *Session) {
	idleMin := int(time.Since(s.LastActiveAt).Minutes())
	prompt := fmt.Sprintf(
		"[系统提示：用户已经 %d 分钟没有说话了，请你主动关心一下用户，说一句温暖的话或发起一个轻松的话题，内容不超过30字，直接输出内容。]",
		idleMin,
	)

	cfg, err := p.channelSvc.ResolveEffectiveConfig(ctx, s.BotID, CompanionType)
	if err != nil {
		p.log.Warn("proactive: failed to resolve channel config",
			slog.String("bot_id", s.BotID),
			slog.String("error", err.Error()),
		)
		cfg = channel.ChannelConfig{}
	}

	msg := channel.InboundMessage{
		Channel: CompanionType,
		Message: channel.Message{
			Parts: []channel.MessagePart{{Type: channel.MessagePartText, Text: prompt}},
		},
		BotID:       s.BotID,
		ReplyTarget: s.ID,
		RouteKey:    s.ID,
		Sender: channel.Identity{
			SubjectID:  s.UserID,
			Attributes: map[string]string{"user_id": s.UserID},
		},
		Conversation: channel.Conversation{
			ID:   s.BotID + ":" + s.UserID,
			Type: "p2p",
		},
		ReceivedAt: time.Now().UTC(),
		Source:     "companion_proactive",
	}

	p.log.Info("sending proactive message",
		slog.String("session_id", s.ID),
		slog.String("bot_id", s.BotID),
		slog.Int("idle_min", idleMin),
	)

	if err := p.channelMgr.HandleInbound(ctx, cfg, msg); err != nil {
		p.log.Error("proactive HandleInbound failed",
			slog.String("session_id", s.ID),
			slog.String("error", err.Error()),
		)
		return
	}
	s.MarkProactiveSent()
}
