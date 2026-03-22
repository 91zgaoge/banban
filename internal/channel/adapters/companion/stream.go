package companion

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"sync/atomic"
	"time"
	"unicode/utf8"

	"github.com/Kxiandaoyan/Memoh-v2/internal/channel"
	"github.com/Kxiandaoyan/Memoh-v2/internal/tts"
)

// wsFrame is the JSON frame sent to the Flutter client over WebSocket.
//
// Down-link frame types:
//
//	status     → {"type":"status","status":"thinking"}
//	delta      → {"type":"delta","text":"..."}
//	final      → {"type":"final","text":"...","duration_ms":N}
//	tts_chunk  → {"type":"tts_chunk","audio":"base64...","seq":N}
//	error      → {"type":"error","message":"..."}
//	pong       → {"type":"pong"}
type wsFrame struct {
	Type       string `json:"type"`
	Status     string `json:"status,omitempty"`
	Text       string `json:"text,omitempty"`
	DurationMs int64  `json:"duration_ms,omitempty"`
	Message    string `json:"message,omitempty"`
	Audio      string `json:"audio,omitempty"`  // base64 encoded audio for tts_chunk
	Seq        int    `json:"seq,omitempty"`    // sequence number for tts_chunk
}

// wsOutboundStream implements channel.OutboundStream by writing JSON frames
// to an active WebSocket session.
//
// Stream event mapping:
//
//	StreamEventStatus  → wsFrame{type:"status", status:...}
//	StreamEventDelta   → wsFrame{type:"delta",  text:delta}
//	StreamEventFinal   → wsFrame{type:"final",  text:plainText}
//	StreamEventError   → wsFrame{type:"error",  message:...}
type wsOutboundStream struct {
	session          *Session
	indexer          *Indexer        // optional; triggers async memory extraction on final
	ttsService       tts.Service     // optional; TTS service for voice output
	textBuf          strings.Builder // accumulates delta text for final message
	sentenceSplitter *tts.SentenceSplitter
	ttsSeq           int
	voiceID          string
	closed           atomic.Bool
	receivedAt       int64 // unix ms when the inbound message was received
}

func newWSOutboundStream(session *Session, indexer *Indexer, ttsService tts.Service, voiceID string, receivedAtMs int64) channel.OutboundStream {
	stream := &wsOutboundStream{
		session:    session,
		indexer:    indexer,
		ttsService: ttsService,
		voiceID:    voiceID,
		receivedAt: receivedAtMs,
	}
	if ttsService != nil {
		stream.sentenceSplitter = tts.NewSentenceSplitter()
	}
	return stream
}

// Push translates a channel.StreamEvent into a WebSocket JSON frame.
func (s *wsOutboundStream) Push(ctx context.Context, event channel.StreamEvent) error {
	if s.closed.Load() {
		return fmt.Errorf("companion: stream is closed")
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	switch event.Type {
	case channel.StreamEventStatus:
		return s.session.WriteJSON(wsFrame{
			Type:   "status",
			Status: string(event.Status),
		})

	case channel.StreamEventDelta:
		if event.Delta != "" {
			s.textBuf.WriteString(event.Delta)
		}
		// Check for complete sentences and trigger TTS
		if s.ttsService != nil && s.sentenceSplitter != nil {
			sentences := s.sentenceSplitter.AddText(event.Delta)
			for _, sentence := range sentences {
				go s.synthesizeAndSend(sentence)
			}
		}
		return s.session.WriteJSON(wsFrame{
			Type: "delta",
			Text: event.Delta,
		})

	case channel.StreamEventFinal:
		text := ""
		if event.Final != nil {
			text = event.Final.Message.PlainText()
		}
		// If the final message is empty but we accumulated deltas, use that.
		if text == "" && s.textBuf.Len() > 0 {
			text = s.textBuf.String()
		}
		// Truncate to valid UTF-8 just in case.
		text = toValidUTF8(text)
		var durationMs int64
		if s.receivedAt > 0 {
			durationMs = time.Now().UnixMilli() - s.receivedAt
		}
		// Flush any remaining text for TTS
		if s.ttsService != nil && s.sentenceSplitter != nil {
			remaining := s.sentenceSplitter.Flush()
			if remaining != "" {
				go s.synthesizeAndSend(remaining)
			}
		}
		// Asynchronously extract and store memories for this turn.
		// Pass ctx so the goroutine inherits the preferred-model context value.
		if s.indexer != nil {
			s.indexer.IndexAsync(ctx, s.session.BotID, s.session.UserID, s.session.UserText, text)
		}
		return s.session.WriteJSON(wsFrame{
			Type:       "final",
			Text:       text,
			DurationMs: durationMs,
		})

	case channel.StreamEventError:
		return s.session.WriteJSON(wsFrame{
			Type:    "error",
			Message: event.Error,
		})
	}
	return nil
}

// Close marks the stream as closed. The WebSocket connection itself is managed
// by the handler and is not closed here.
func (s *wsOutboundStream) Close(_ context.Context) error {
	s.closed.Store(true)
	s.textBuf.Reset()
	return nil
}

// toValidUTF8 removes invalid UTF-8 sequences.
func toValidUTF8(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		b.WriteRune(r)
	}
	return b.String()
}

// synthesizeAndSend performs TTS synthesis and sends the audio chunk to the client.
func (s *wsOutboundStream) synthesizeAndSend(text string) {
	if s.ttsService == nil || text == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	audioData, err := s.ttsService.Synthesize(ctx, text, s.voiceID)
	if err != nil {
		// Log error but don't fail the stream
		return
	}

	if len(audioData) == 0 {
		return
	}

	s.ttsSeq++
	s.session.WriteJSON(wsFrame{
		Type:  "tts_chunk",
		Audio: base64.StdEncoding.EncodeToString(audioData),
		Seq:   s.ttsSeq,
	})
}
