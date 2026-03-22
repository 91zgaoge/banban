package companion

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
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
//	tts_chunk  → {"type":"tts_chunk","seq":N,"chunk":N,"audio":"base64..."}
//	tts_done   → {"type":"tts_done","seq":N}
//	tts_error  → {"type":"tts_error","seq":N,"message":"..."}
//	error      → {"type":"error","message":"..."}
//	pong       → {"type":"pong"}
//	proactive  → {"type":"proactive","text":"..."}
type wsFrame struct {
	Type       string `json:"type"`
	Status     string `json:"status,omitempty"`
	Text       string `json:"text,omitempty"`
	DurationMs int64  `json:"duration_ms,omitempty"`
	Message    string `json:"message,omitempty"`
	Audio      string `json:"audio,omitempty"` // base64 encoded audio chunk
	Seq        int32  `json:"seq,omitempty"`   // TTS sentence sequence number
	Chunk      int    `json:"chunk,omitempty"` // chunk index within a sentence
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
	indexer          *Indexer            // optional; triggers async memory extraction on final
	ttsService       tts.Service         // optional; TTS service for voice output
	textBuf          strings.Builder     // accumulates delta text for final message
	sentenceSplitter *tts.SentenceSplitter
	ttsSeq           atomic.Int32        // atomic sentence sequence counter
	voiceID          string
	closed           atomic.Bool
	receivedAt       int64               // unix ms when the inbound message was received
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
		// Check for complete sentences and trigger TTS.
		if s.ttsService != nil && s.sentenceSplitter != nil {
			for _, sentence := range s.sentenceSplitter.AddText(event.Delta) {
				seq := s.ttsSeq.Add(1)
				go s.synthesizeAndSendStream(sentence, seq)
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
		if text == "" && s.textBuf.Len() > 0 {
			text = s.textBuf.String()
		}
		text = toValidUTF8(text)
		var durationMs int64
		if s.receivedAt > 0 {
			durationMs = time.Now().UnixMilli() - s.receivedAt
		}
		// Flush remaining text for TTS.
		if s.ttsService != nil && s.sentenceSplitter != nil {
			if remaining := s.sentenceSplitter.Flush(); remaining != "" {
				seq := s.ttsSeq.Add(1)
				go s.synthesizeAndSendStream(remaining, seq)
			}
		}
		// Async memory extraction.
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

// Close marks the stream as closed.
func (s *wsOutboundStream) Close(_ context.Context) error {
	s.closed.Store(true)
	s.textBuf.Reset()
	return nil
}

// toValidUTF8 removes invalid UTF-8 sequences.
func toValidUTF8(str string) string {
	if utf8.ValidString(str) {
		return str
	}
	var b strings.Builder
	b.Grow(len(str))
	for _, r := range str {
		b.WriteRune(r)
	}
	return b.String()
}

// synthesizeAndSendStream performs streaming TTS synthesis and pushes
// audio chunks to the client as they arrive from Kokoro.
// Chunks are sent with the format:
//
//	{"type":"tts_chunk","seq":N,"chunk":M,"audio":"<base64>"}
//	{"type":"tts_done","seq":N}
func (s *wsOutboundStream) synthesizeAndSendStream(text string, seq int32) {
	if s.ttsService == nil || text == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	reader, err := s.ttsService.SynthesizeStream(ctx, text, s.voiceID)
	if err != nil {
		_ = s.session.WriteJSON(wsFrame{
			Type:    "tts_error",
			Seq:     seq,
			Message: err.Error(),
		})
		return
	}
	defer reader.Close()

	const chunkSize = 4096
	buf := make([]byte, chunkSize)
	chunkIdx := 0

	for {
		n, readErr := reader.Read(buf)
		if n > 0 {
			_ = s.session.WriteJSON(wsFrame{
				Type:  "tts_chunk",
				Seq:   seq,
				Chunk: chunkIdx,
				Audio: base64.StdEncoding.EncodeToString(buf[:n]),
			})
			chunkIdx++
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			_ = s.session.WriteJSON(wsFrame{
				Type:    "tts_error",
				Seq:     seq,
				Message: readErr.Error(),
			})
			return
		}
	}

	_ = s.session.WriteJSON(wsFrame{Type: "tts_done", Seq: seq})
}
