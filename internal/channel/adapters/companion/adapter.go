package companion

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/Kxiandaoyan/Memoh-v2/internal/channel"
	"github.com/Kxiandaoyan/Memoh-v2/internal/tts"
)

// Adapter is the Companion channel adapter. It implements channel.Adapter and
// channel.StreamSender, enabling the BanBan Flutter app to communicate with the
// bot engine over WebSocket.
//
// Each connected Flutter client is registered as a Session in the SessionHub.
// When the channel manager calls OpenStream, the adapter looks up the session
// by target (session ID) and returns a wsOutboundStream backed by that WebSocket.
type Adapter struct {
	hub        *SessionHub
	indexer    *Indexer    // optional; nil disables memory indexing
	ttsService tts.Service // optional; nil disables TTS
	voiceID    string      // default voice for TTS
}

// NewAdapter creates a Companion adapter backed by the given SessionHub.
// Pass a non-nil Indexer to enable post-conversation memory extraction.
// Pass a non-nil TTS service to enable voice output.
func NewAdapter(hub *SessionHub, indexer *Indexer, ttsService tts.Service, voiceID string) *Adapter {
	if voiceID == "" {
		voiceID = "af_bella" // default voice
	}
	return &Adapter{hub: hub, indexer: indexer, ttsService: ttsService, voiceID: voiceID}
}

// Type returns the Companion channel type identifier.
func (a *Adapter) Type() channel.ChannelType {
	return CompanionType
}

// Descriptor returns static metadata for the Companion channel.
func (a *Adapter) Descriptor() channel.Descriptor {
	return channel.Descriptor{
		Type:        CompanionType,
		DisplayName: "伴伴（Companion）",
		Configless:  true,
		Capabilities: channel.ChannelCapabilities{
			Text:           true,
			Attachments:    true,
			Streaming:      true,
			BlockStreaming:  true,
		},
		TargetSpec: channel.TargetSpec{
			Format: "session_id",
			Hints: []channel.TargetHint{
				{Label: "Session ID", Example: "uuid-v4"},
			},
		},
	}
}

// OpenStream returns a WebSocket-backed outbound stream for the given session ID.
//
// target is the session ID registered in SessionHub by the CompanionHandler when
// the client connected.
func (a *Adapter) OpenStream(ctx context.Context, cfg channel.ChannelConfig, target string, opts channel.StreamOptions) (channel.OutboundStream, error) {
	if a.hub == nil {
		return nil, fmt.Errorf("companion: session hub not configured")
	}
	target = strings.TrimSpace(target)
	if target == "" {
		return nil, fmt.Errorf("companion: target session ID is required")
	}
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	session, err := a.hub.Get(target)
	if err != nil {
		return nil, fmt.Errorf("companion: %w", err)
	}

	var receivedAtMs int64
	if !opts.ReceivedAt.IsZero() {
		receivedAtMs = opts.ReceivedAt.UnixMilli()
	} else {
		receivedAtMs = time.Now().UnixMilli()
	}

	return newWSOutboundStream(session, a.indexer, a.ttsService, a.voiceID, receivedAtMs), nil
}
